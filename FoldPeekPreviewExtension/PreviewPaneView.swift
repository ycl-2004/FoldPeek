import AppKit

/// The content pane: one item, printed on paper.
final class PreviewPaneView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let badge = TypeBadgeView()
    private let metaLabel = NSTextField(labelWithString: "")
    private let card = PaperCardView()
    private let metadata = MetadataGridView()

    private let placeholderIcon = NSImageView()
    private let placeholderLabel = NSTextField(wrappingLabelWithString: "")
    private let placeholderStack = NSStackView()
    private let textScrollView = NSScrollView()
    private let textView = CodeTextView()
    private var lineRuler: LineNumberRulerView?
    private let imageScrollView = NSScrollView()
    private let imageView = NSImageView()
    private let pdfView = PaperPDFView()
    private let renderedPage = RenderedPageView()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        assemblePane()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        assemblePane()
    }

    // MARK: - States

    func showEmptySelection() {
        titleLabel.stringValue = "未选择条目"
        badge.text = ""
        metaLabel.stringValue = "—"
        metadata.clear()
        presentPlaceholder(symbol: "sidebar.left", message: "在左侧索引中选择一个条目。")
    }

    func showFolder(_ item: IndexedEntry, childCount: Int?, isExpanded: Bool = false) {
        titleLabel.stringValue = item.name
        badge.accent = FileCategory.of(item).color
        badge.text = item.isSymbolicLink ? "LINK" : "DIR"
        metaLabel.stringValue = [
            item.isSymbolicLink ? "Symbolic Link" : "Folder",
            childCount.map { "\($0) 项" },
            item.formattedModificationDate
        ]
        .compactMap { $0 }
        .joined(separator: "  ·  ")

        metadata.update(
            kind: item.kind,
            size: "—",
            modified: item.formattedModificationDate,
            isSymbolicLink: item.isSymbolicLink,
            location: Self.displayPath(for: item)
        )

        if item.isSymbolicLink {
            presentPlaceholder(symbol: "link", message: "不跟随符号链接。\nFoldPeek 只显示它，不进入它。")
        } else if isExpanded {
            let count = childCount.map { "共 \($0) 项。" } ?? ""
            presentPlaceholder(symbol: "folder", message: "已展开。\(count)\n再次点击此行可折叠。")
        } else {
            presentPlaceholder(symbol: "folder", message: "点击此行可展开，\n查看其中的内容。")
        }
    }

    func showFile(_ item: IndexedEntry, result: FilePreviewResult) {
        let category = FileCategory.of(item)
        titleLabel.stringValue = item.name
        badge.text = Self.badgeText(for: item)
        badge.accent = category.color

        var parts: [String] = [result.typeDescription]
        if let byteSize = result.byteSize {
            parts.append(ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file))
        }
        parts.append(item.formattedModificationDate)

        metadata.update(
            kind: result.typeDescription,
            size: result.byteSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—",
            modified: item.formattedModificationDate,
            isSymbolicLink: item.isSymbolicLink,
            location: Self.displayPath(for: item)
        )

        switch result.content {
        case let .text(text, isTruncated):
            setVisibleContent(.text)
            applyText(text, pathExtension: item.url.pathExtension)
            if isTruncated {
                let cap = ByteCountFormatter.string(
                    fromByteCount: Int64(FilePreviewLoader.maximumTextBytes),
                    countStyle: .file
                )
                parts.append("仅显示前 \(cap)")
            }

        case let .richText(document, isTruncated):
            setVisibleContent(.text)
            applyProse(document)
            if isTruncated {
                parts.append("仅显示前 \(RichDocumentReader.maximumCharacters) 字")
            }

        case let .image(image, pixelWidth, pixelHeight):
            setVisibleContent(.image)
            imageView.image = image
            if pixelWidth > 0, pixelHeight > 0 {
                parts.append("\(pixelWidth) × \(pixelHeight)")
            }

        case let .pdf(document, pageCount):
            setVisibleContent(.pdf)
            pdfView.showDocument(document)
            parts.append("\(pageCount) 页")

        case let .rendered(image, note):
            setVisibleContent(.rendered)
            renderedPage.image = image
            parts.append(note)

        case let .unavailable(reason):
            presentPlaceholder(symbol: "eye.slash", message: reason, tint: category.color)
        }

        metaLabel.stringValue = parts.joined(separator: "  ·  ")
    }

    func showLoading() {
        presentPlaceholder(symbol: "hourglass", message: "读取中…")
    }

    // MARK: - Content switching

    private enum VisibleContent {
        case placeholder, text, image, pdf, rendered
    }

    private func presentPlaceholder(
        symbol: String,
        message: String,
        tint: NSColor = PaperTheme.denim
    ) {
        setVisibleContent(.placeholder)
        placeholderIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 30, weight: .light))
        placeholderIcon.contentTintColor = tint
        placeholderLabel.stringValue = message
    }

    /// Markdown is laid out as prose; everything else is shown as source.
    private func applyText(_ text: String, pathExtension: String) {
        if MarkdownRenderer.canRender(pathExtension: pathExtension),
           let rendered = MarkdownRenderer.render(text) {
            setProseMode(true)
            textView.textStorage?.setAttributedString(rendered)
        } else {
            setProseMode(false)
            let font = PaperTheme.mono(11)
            let attributed = CodeHighlighter.highlight(text: text, pathExtension: pathExtension, font: font)
                ?? NSAttributedString(
                    string: text,
                    attributes: [.font: font, .foregroundColor: PaperTheme.Syntax.plain]
                )
            textView.textStorage?.setAttributedString(attributed)
            textView.refreshCodeMetrics()
            lineRuler?.refresh(for: text as NSString)
        }
        textView.scroll(.zero)
    }

    /// A document that arrived already typeset — Word, RTF, OpenDocument —
    /// takes the same prose treatment Markdown does.
    private func applyProse(_ document: NSAttributedString) {
        setProseMode(true)
        textView.textStorage?.setAttributedString(document)
        textView.scroll(.zero)
    }

    /// Prose and source want opposite treatments. Source keeps the gutter, the
    /// guides, and the ruled grain. Prose drops all three — ruled paper behind
    /// running text is what makes a long document hard to read — and is held to
    /// a reading measure instead of filling a wide panel edge to edge.
    private func setProseMode(_ isProse: Bool) {
        card.drawsGrain = !isProse
        textView.drawsIndentGuides = !isProse
        textScrollView.rulersVisible = !isProse
        textView.baseInset = isProse
            ? NSSize(width: 30, height: 26)
            : NSSize(width: 10, height: 10)
        textView.maximumReadingWidth = isProse ? PaperTheme.readingWidth : nil
    }

    private func setVisibleContent(_ content: VisibleContent) {
        placeholderStack.isHidden = content != .placeholder
        textScrollView.isHidden = content != .text
        imageScrollView.isHidden = content != .image
        pdfView.isHidden = content != .pdf
        renderedPage.isHidden = content != .rendered

        // A PDF and a rendered page carry their own paper; ruling the card
        // behind them would print one sheet on top of another. Prose turns the
        // grain off separately, after this runs.
        card.drawsGrain = content != .pdf && content != .rendered

        // Releases whichever payload is no longer on screen. A PDF is the
        // heaviest of them: PDFKit maps the file and caches rendered pages for
        // as long as the document is attached.
        if content != .text { textView.string = "" }
        if content != .image { imageView.image = nil }
        if content != .pdf { pdfView.unload() }
        if content != .rendered { renderedPage.image = nil }
    }

    private static func badgeText(for item: IndexedEntry) -> String {
        if item.isSymbolicLink { return "LINK" }
        let ext = item.url.pathExtension.uppercased()
        guard !ext.isEmpty, ext.count <= 5 else { return "FILE" }
        return ext
    }

    private static func displayPath(for item: IndexedEntry) -> String {
        (item.url.path as NSString).abbreviatingWithTildeInPath
    }

    // MARK: - Layout

    private func assemblePane() {
        wantsLayer = true
        layer?.backgroundColor = PaperTheme.paper.cgColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = PaperTheme.serif(21, weight: .medium)
        titleLabel.textColor = PaperTheme.ink
        titleLabel.lineBreakMode = .byTruncatingMiddle

        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)

        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        metaLabel.font = PaperTheme.mono(10)
        metaLabel.textColor = PaperTheme.inkSoft
        metaLabel.lineBreakMode = .byTruncatingTail

        card.translatesAutoresizingMaskIntoConstraints = false
        metadata.translatesAutoresizingMaskIntoConstraints = false

        configurePlaceholder()
        configureTextView()
        configureImageView()
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        renderedPage.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(placeholderStack)
        card.addSubview(textScrollView)
        card.addSubview(imageScrollView)
        card.addSubview(pdfView)
        card.addSubview(renderedPage)

        addSubview(titleLabel)
        addSubview(badge)
        addSubview(metaLabel)
        addSubview(card)
        addSubview(metadata)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),

            badge.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            badge.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 7),
            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            card.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 18),
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            metadata.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 20),
            metadata.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            metadata.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            metadata.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),

            placeholderStack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            placeholderStack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            placeholderStack.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor, constant: 24),
            placeholderStack.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -24)
        ])

        for content in [textScrollView, imageScrollView, pdfView, renderedPage] as [NSView] {
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
                content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
                content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
                content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10)
            ])
        }

        showEmptySelection()
    }

    private func configurePlaceholder() {
        placeholderIcon.translatesAutoresizingMaskIntoConstraints = false
        placeholderIcon.imageScaling = .scaleNone

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.alignment = .center
        placeholderLabel.font = PaperTheme.serif(12)
        placeholderLabel.textColor = PaperTheme.inkSoft
        placeholderLabel.maximumNumberOfLines = 0

        placeholderStack.translatesAutoresizingMaskIntoConstraints = false
        placeholderStack.orientation = .vertical
        placeholderStack.alignment = .centerX
        placeholderStack.spacing = 16
        placeholderStack.addArrangedSubview(placeholderIcon)
        placeholderStack.addArrangedSubview(placeholderLabel)
        placeholderLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300).isActive = true
    }

    private func configureTextView() {
        textView.isEditable = false
        textView.isSelectable = true
        // Plain characters only: no RTF, no attributed payloads, no data detectors.
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = PaperTheme.mono(11)
        textView.textColor = PaperTheme.ink
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.drawsBackground = false
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        textScrollView.translatesAutoresizingMaskIntoConstraints = false
        textScrollView.documentView = textView
        textScrollView.hasVerticalScroller = true
        textScrollView.autohidesScrollers = true
        textScrollView.borderType = .noBorder
        textScrollView.drawsBackground = false

        let ruler = LineNumberRulerView(textView: textView, scrollView: textScrollView)
        textScrollView.hasVerticalRuler = true
        textScrollView.rulersVisible = true
        textScrollView.verticalRulerView = ruler
        lineRuler = ruler
    }

    private func configureImageView() {
        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignCenter

        imageScrollView.translatesAutoresizingMaskIntoConstraints = false
        imageScrollView.documentView = imageView
        imageScrollView.hasVerticalScroller = false
        imageScrollView.borderType = .noBorder
        imageScrollView.drawsBackground = false
        imageView.autoresizingMask = [.width, .height]
    }
}
