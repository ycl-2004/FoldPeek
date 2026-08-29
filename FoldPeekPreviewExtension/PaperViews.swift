import AppKit

// MARK: - Paper card

/// The content pane's preview surface: a rounded sheet with a faint 22 pt
/// grain and a hairline edge. Content views are added as ordinary subviews.
final class PaperCardView: NSView {
    /// Prose turns the grain off — ruled paper competes with running text and
    /// makes long documents harder to read.
    var drawsGrain = true {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: bounds, xRadius: PaperTheme.cardCornerRadius, yRadius: PaperTheme.cardCornerRadius)

        PaperTheme.paper.setFill()
        path.fill()

        if drawsGrain {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            drawGrain(in: bounds)
            NSGraphicsContext.restoreGraphicsState()
        }

        PaperTheme.hairline.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawGrain(in rect: NSRect) {
        let spacing = PaperTheme.paperGrainSpacing
        let grid = NSBezierPath()
        grid.lineWidth = 1

        var x = rect.minX + spacing
        while x < rect.maxX {
            grid.move(to: NSPoint(x: x.rounded() + 0.5, y: rect.minY))
            grid.line(to: NSPoint(x: x.rounded() + 0.5, y: rect.maxY))
            x += spacing
        }

        var y = rect.minY + spacing
        while y < rect.maxY {
            grid.move(to: NSPoint(x: rect.minX, y: y.rounded() + 0.5))
            grid.line(to: NSPoint(x: rect.maxX, y: y.rounded() + 0.5))
            y += spacing
        }

        PaperTheme.hairlineFaint.setStroke()
        grid.stroke()
    }
}

// MARK: - Split view

/// A split view whose divider is a hairline pinned between two wine diamonds.
///
/// The thickness is larger than the drawn line on purpose: it is the drag
/// target, and a one-point divider is close to impossible to grab.
final class DiamondSplitView: NSSplitView {
    private let diamondRadius: CGFloat = 4.5
    private let diamondInset: CGFloat = 6

    override var dividerThickness: CGFloat { 11 }
    override var dividerColor: NSColor { .clear }

    override func drawDivider(in rect: NSRect) {
        PaperTheme.hairline.setFill()
        let line = NSRect(x: rect.midX - 0.5, y: rect.minY, width: 1, height: rect.height)
        line.fill()

        drawDiamond(centeredAt: NSPoint(x: rect.midX, y: rect.minY + diamondInset))
        drawDiamond(centeredAt: NSPoint(x: rect.midX, y: rect.maxY - diamondInset))
    }

    private func drawDiamond(centeredAt center: NSPoint) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center.x, y: center.y - diamondRadius))
        path.line(to: NSPoint(x: center.x + diamondRadius, y: center.y))
        path.line(to: NSPoint(x: center.x, y: center.y + diamondRadius))
        path.line(to: NSPoint(x: center.x - diamondRadius, y: center.y))
        path.close()
        PaperTheme.wine.setFill()
        path.fill()
    }
}

// MARK: - Index list

/// An outline view with no disclosure triangles.
///
/// A click anywhere on a folder row already opens it, so the triangle was a
/// second, smaller target for the same action — indentation and the folder
/// glyph carry the hierarchy instead.
final class IndexOutlineView: NSOutlineView {
    override func frameOfOutlineCell(atRow row: Int) -> NSRect { .zero }
}

// MARK: - Index rows

/// Selection is a soft denim block with a wine marker on the trailing edge.
final class IndexRowView: NSTableRowView {
    /// Headings are not selectable and take no selection block.
    var isHeading = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func drawSelection(in dirtyRect: NSRect) {
        guard !isHeading else { return }
        guard selectionHighlightStyle != .none else { return }

        let block = bounds.insetBy(dx: 6, dy: 1)
        let path = NSBezierPath(
            roundedRect: block,
            xRadius: PaperTheme.rowCornerRadius,
            yRadius: PaperTheme.rowCornerRadius
        )
        PaperTheme.denimSoft.setFill()
        path.fill()

        let marker = NSRect(x: block.maxX - 3, y: block.minY, width: 3, height: block.height)
        PaperTheme.wine.setFill()
        NSBezierPath(roundedRect: marker, xRadius: 1.5, yRadius: 1.5).fill()
    }

}

/// One index row: a folder glyph or a wine type mark, a serif name, and a
/// right-aligned monospaced figure.
final class IndexCellView: NSTableCellView {
    let glyphView = NSImageView()
    let typeLabel = NSTextField(labelWithString: "")
    let nameLabel = NSTextField(labelWithString: "")
    let trailingLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        assembleRow()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        assembleRow()
    }

    func showFolder(symbol: String, tint: NSColor) {
        glyphView.isHidden = false
        typeLabel.isHidden = true
        glyphView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        glyphView.contentTintColor = tint
    }

    /// The extension tag, printed in its category's ink on a wash of the same
    /// hue. The chip is what turns a column of filenames into something you can
    /// scan by kind without reading a single word.
    func showType(_ text: String, color: NSColor) {
        glyphView.isHidden = true
        typeLabel.isHidden = false
        typeLabel.stringValue = text
        typeLabel.textColor = color
        chipColor = color
        needsDisplay = true
    }

    private var chipColor: NSColor?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !typeLabel.isHidden, let chipColor else { return }

        let chip = typeLabel.frame.insetBy(dx: 0, dy: -3.5)
        let path = NSBezierPath(roundedRect: chip, xRadius: 3, yRadius: 3)
        chipColor.withAlphaComponent(PaperTheme.Category.chipFill).setFill()
        path.fill()
        chipColor.withAlphaComponent(PaperTheme.Category.chipStroke).setStroke()
        path.lineWidth = 0.75
        path.stroke()
    }

    private func assembleRow() {
        glyphView.translatesAutoresizingMaskIntoConstraints = false
        glyphView.imageScaling = .scaleProportionallyDown

        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        typeLabel.font = PaperTheme.mono(8, weight: .medium)
        typeLabel.textColor = PaperTheme.wine
        typeLabel.alignment = .center
        typeLabel.lineBreakMode = .byClipping

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = PaperTheme.serif(13)
        nameLabel.textColor = PaperTheme.ink
        nameLabel.lineBreakMode = .byTruncatingMiddle

        trailingLabel.translatesAutoresizingMaskIntoConstraints = false
        trailingLabel.font = PaperTheme.mono(10)
        trailingLabel.textColor = PaperTheme.inkFaint
        trailingLabel.alignment = .right
        trailingLabel.setContentHuggingPriority(.required, for: .horizontal)
        trailingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(glyphView)
        addSubview(typeLabel)
        addSubview(nameLabel)
        addSubview(trailingLabel)
        textField = nameLabel

        NSLayoutConstraint.activate([
            glyphView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glyphView.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyphView.widthAnchor.constraint(equalToConstant: 26),

            typeLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            typeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            typeLabel.widthAnchor.constraint(equalToConstant: 26),

            nameLabel.leadingAnchor.constraint(equalTo: glyphView.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            trailingLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 10),
            trailingLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            trailingLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

// MARK: - Category legend

/// One pill in the legend: a dot in the category's ink, its Latin tag, and how
/// many rows carry it.
final class CategoryPillView: NSView {
    let category: FileCategory
    private let count: Int
    private var isPressed = false

    var onSelect: ((FileCategory) -> Void)?

    override var isFlipped: Bool { true }

    init(category: FileCategory, count: Int) {
        self.category = category
        self.count = count
        super.init(frame: .zero)
        toolTip = "\(category.title) · \(count)"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    private var label: NSAttributedString {
        NSAttributedString(
            string: "\(category.tag)  \(count)",
            attributes: [
                .font: PaperTheme.mono(8, weight: .medium),
                .foregroundColor: category.color
            ]
        )
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: (label.size().width + 26).rounded(), height: 19)
    }

    override func draw(_ dirtyRect: NSRect) {
        let body = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: body, xRadius: 4, yRadius: 4)
        category.color.withAlphaComponent(isPressed ? 0.22 : 0.10).setFill()
        path.fill()
        category.color.withAlphaComponent(0.25).setStroke()
        path.lineWidth = 0.75
        path.stroke()

        let dot = NSRect(x: 7, y: bounds.midY - 2.5, width: 5, height: 5)
        category.color.setFill()
        NSBezierPath(ovalIn: dot).fill()

        label.draw(at: NSPoint(x: 17, y: (bounds.height - label.size().height) / 2))
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        needsDisplay = true
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onSelect?(category)
        }
    }
}

/// The strip under the search field: every group present in this folder, in
/// order, as a jump target.
///
/// It earns its space twice — it is the key that explains what the colours in
/// the list mean, and it is how you reach the eleventh group without dragging
/// a scroller past the first ten.
final class CategoryLegendView: NSView {
    var onSelect: ((FileCategory) -> Void)?

    private var pills: [CategoryPillView] = []
    private let pillSpacing: CGFloat = 5
    private let rowSpacing: CGFloat = 5

    override var isFlipped: Bool { true }

    func update(_ groups: [(category: FileCategory, count: Int)]) {
        pills.forEach { $0.removeFromSuperview() }
        pills = groups.map { group in
            let pill = CategoryPillView(category: group.category, count: group.count)
            pill.onSelect = { [weak self] in self?.onSelect?($0) }
            addSubview(pill)
            return pill
        }
        isHidden = pills.count < 2
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: flow(placing: false))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        invalidateIntrinsicContentSize()
    }

    override func layout() {
        super.layout()
        _ = flow(placing: true)
    }

    /// Wraps the pills across as many rows as the width needs, and returns the
    /// height that took. The same pass measures and places, so the intrinsic
    /// height can never disagree with what is drawn.
    @discardableResult
    private func flow(placing: Bool) -> CGFloat {
        guard !pills.isEmpty else { return 0 }
        let maximumWidth = max(bounds.width, 1)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for pill in pills {
            let size = pill.intrinsicContentSize
            if x > 0, x + size.width > maximumWidth {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            if placing {
                pill.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
            }
            x += size.width + pillSpacing
            rowHeight = max(rowHeight, size.height)
        }
        return y + rowHeight
    }
}

// MARK: - Group heading

/// The heading above one file group: a coloured rule, the category's name, its
/// Latin tag, a leader rule, and the count.
///
/// The vertical rule repeats the wine bar beside the FoldPeek wordmark, one
/// level down and in the group's own hue — the same device saying the same
/// thing about a smaller piece of the page.
final class IndexGroupHeaderView: NSTableCellView {
    private let rule = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let tagLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private var accent: NSColor = PaperTheme.inkSoft

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        assembleHeader()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        assembleHeader()
    }

    func update(category: FileCategory, count: Int) {
        accent = category.color
        rule.layer?.backgroundColor = accent.cgColor
        titleLabel.stringValue = category.title
        titleLabel.textColor = accent
        tagLabel.stringValue = category.tag
        tagLabel.textColor = accent.withAlphaComponent(0.5)
        countLabel.stringValue = "\(count)"
        needsDisplay = true
    }

    /// The leader between the tag and the count, drawn rather than laid out so
    /// it always fills exactly the gap that is left.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let start = tagLabel.frame.maxX + 8
        let end = countLabel.frame.minX - 8
        guard end > start else { return }
        accent.withAlphaComponent(0.18).setFill()
        NSRect(x: start, y: bounds.midY - 0.5, width: end - start, height: 1).fill()
    }

    private func assembleHeader() {
        rule.translatesAutoresizingMaskIntoConstraints = false
        rule.wantsLayer = true
        rule.layer?.cornerRadius = 1.5

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = PaperTheme.serif(11.5, weight: .medium)

        tagLabel.translatesAutoresizingMaskIntoConstraints = false
        tagLabel.font = PaperTheme.mono(8, weight: .medium)

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = PaperTheme.mono(9)
        countLabel.textColor = PaperTheme.inkFaint
        countLabel.alignment = .right
        countLabel.setContentHuggingPriority(.required, for: .horizontal)

        for subview in [rule, titleLabel, tagLabel, countLabel] {
            addSubview(subview)
        }

        NSLayoutConstraint.activate([
            rule.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            rule.centerYAnchor.constraint(equalTo: centerYAnchor),
            rule.widthAnchor.constraint(equalToConstant: 3),
            rule.heightAnchor.constraint(equalToConstant: 13),

            titleLabel.leadingAnchor.constraint(equalTo: rule.trailingAnchor, constant: 9),
            titleLabel.firstBaselineAnchor.constraint(equalTo: tagLabel.firstBaselineAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0.5),

            tagLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 7),

            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: tagLabel.trailingAnchor, constant: 10)
        ])
    }
}

// MARK: - Type badge

/// The wine outlined pill in the inspector header.
final class TypeBadgeView: NSView {
    private let label = NSTextField(labelWithString: "")

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        assembleBadge()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        assembleBadge()
    }

    var text: String = "" {
        didSet {
            label.stringValue = text
            isHidden = text.isEmpty
            needsDisplay = true
        }
    }

    /// Carries the selected item's category hue, so the inspector header and
    /// the index row agree about what kind of thing is on screen.
    var accent: NSColor = PaperTheme.wine {
        didSet {
            label.textColor = accent
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else { return }
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        accent.withAlphaComponent(0.10).setFill()
        path.fill()
        accent.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func assembleBadge() {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = PaperTheme.mono(9, weight: .medium)
        label.textColor = PaperTheme.wine
        label.alignment = .center
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 20)
        ])
    }
}
