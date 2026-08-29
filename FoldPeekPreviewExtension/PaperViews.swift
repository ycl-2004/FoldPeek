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
    /// Set on the first file after the folder group, to print the divide.
    var showsTopSeparator = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func drawSelection(in dirtyRect: NSRect) {
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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsTopSeparator else { return }
        PaperTheme.hairline.setFill()
        NSRect(x: 14, y: 0, width: bounds.width - 28, height: 1).fill()
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

    func showType(_ text: String) {
        glyphView.isHidden = true
        typeLabel.isHidden = false
        typeLabel.stringValue = text
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

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else { return }
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        PaperTheme.wine.withAlphaComponent(0.45).setStroke()
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
