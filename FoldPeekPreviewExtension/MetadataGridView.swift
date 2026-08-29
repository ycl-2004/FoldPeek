import AppKit

/// The inspector's footing: a two-column ledger of the selected item's facts.
final class MetadataGridView: NSView {
    private let kindValue = MetadataGridView.valueLabel(alignment: .left)
    private let sizeValue = MetadataGridView.valueLabel(alignment: .right)
    private let modifiedValue = MetadataGridView.valueLabel(alignment: .left)
    private let symlinkValue = MetadataGridView.valueLabel(alignment: .right)
    private let locationValue = MetadataGridView.valueLabel(alignment: .left)
    private let assuranceLabel = NSTextField(labelWithString: "read-only · sandboxed")

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        assembleGrid()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        assembleGrid()
    }

    func update(kind: String, size: String, modified: String, isSymbolicLink: Bool, location: String) {
        kindValue.stringValue = kind
        sizeValue.stringValue = size
        modifiedValue.stringValue = modified
        symlinkValue.stringValue = isSymbolicLink ? "是" : "否"
        locationValue.stringValue = location
    }

    func clear() {
        for label in [kindValue, sizeValue, modifiedValue, symlinkValue, locationValue] {
            label.stringValue = "—"
        }
    }

    // MARK: - Layout

    private func assembleGrid() {
        locationValue.textColor = PaperTheme.denim
        locationValue.lineBreakMode = .byTruncatingMiddle

        assuranceLabel.translatesAutoresizingMaskIntoConstraints = false
        assuranceLabel.font = PaperTheme.mono(9)
        assuranceLabel.textColor = PaperTheme.inkFaint
        assuranceLabel.alignment = .right

        let firstRow = row(
            leftLabel: "种类", leftValue: kindValue,
            rightLabel: "大小", rightValue: sizeValue
        )
        let secondRow = row(
            leftLabel: "变更日", leftValue: modifiedValue,
            rightLabel: "符号链接", rightValue: symlinkValue
        )
        let thirdRow = locationRow()

        let stack = NSStackView(views: [firstRow, secondRow, thirdRow])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 0
        stack.distribution = .fill
        stack.alignment = .leading
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        for rowView in [firstRow, secondRow, thirdRow] {
            rowView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        clear()
    }

    /// Two label/value pairs side by side, ruled off underneath.
    private func row(
        leftLabel: String,
        leftValue: NSTextField,
        rightLabel: String,
        rightValue: NSTextField
    ) -> NSView {
        let container = RuledRowView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let leftKey = Self.keyLabel(leftLabel)
        let rightKey = Self.keyLabel(rightLabel)
        for view in [leftKey, leftValue, rightKey, rightValue] {
            container.addSubview(view)
        }

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 30),

            leftKey.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            leftKey.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            leftKey.widthAnchor.constraint(equalToConstant: 58),

            leftValue.leadingAnchor.constraint(equalTo: leftKey.trailingAnchor, constant: 10),
            leftValue.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            leftValue.trailingAnchor.constraint(lessThanOrEqualTo: container.centerXAnchor, constant: -16),

            rightKey.leadingAnchor.constraint(equalTo: container.centerXAnchor, constant: 16),
            rightKey.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            rightKey.widthAnchor.constraint(equalToConstant: 62),

            rightValue.leadingAnchor.constraint(equalTo: rightKey.trailingAnchor, constant: 10),
            rightValue.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rightValue.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    /// The path row: one wide value plus the sandbox assurance.
    private func locationRow() -> NSView {
        let container = RuledRowView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.drawsRule = false

        let key = Self.keyLabel("位置")
        container.addSubview(key)
        container.addSubview(locationValue)
        container.addSubview(assuranceLabel)

        assuranceLabel.setContentHuggingPriority(.required, for: .horizontal)
        assuranceLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 30),

            key.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            key.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            key.widthAnchor.constraint(equalToConstant: 58),

            locationValue.leadingAnchor.constraint(equalTo: key.trailingAnchor, constant: 10),
            locationValue.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            assuranceLabel.leadingAnchor.constraint(greaterThanOrEqualTo: locationValue.trailingAnchor, constant: 12),
            assuranceLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            assuranceLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private static func keyLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = PaperTheme.serif(11)
        label.textColor = PaperTheme.inkSoft
        return label
    }

    private static func valueLabel(alignment: NSTextAlignment) -> NSTextField {
        let label = NSTextField(labelWithString: "—")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = PaperTheme.mono(10)
        label.textColor = PaperTheme.ink
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}

/// A row ruled off with a hairline along its bottom edge.
private final class RuledRowView: NSView {
    var drawsRule = true

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard drawsRule else { return }
        PaperTheme.hairline.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }
}
