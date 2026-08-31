import AppKit

/// The control strip above a spreadsheet: which way to look at it, and which
/// sheet to look at.
///
/// It appears only for workbooks, and the sheet tabs only when there is more
/// than one — a single-sheet file gets no row of one tab.
final class WorkbookBarView: NSView {
    enum Mode {
        case page
        case table
    }

    var onSelectMode: ((Mode) -> Void)?
    var onSelectSheet: ((Int) -> Void)?

    private let pageButton = ModeButton(title: "页面")
    private let tableButton = ModeButton(title: "表格")
    private var tabs: [SheetTabView] = []
    private var showsModeToggle = true

    private let tabSpacing: CGFloat = 5
    private let rowSpacing: CGFloat = 5
    private let controlHeight: CGFloat = 20

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        assemble()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        assemble()
    }

    private func assemble() {
        pageButton.onSelect = { [weak self] in self?.onSelectMode?(.page) }
        tableButton.onSelect = { [weak self] in self?.onSelectMode?(.table) }
        addSubview(pageButton)
        addSubview(tableButton)
    }

    /// - Parameter hasPage: false when the file yielded no page image, in which
    ///   case the toggle is pointless and the table is all there is.
    func update(sheetNames: [String], selectedSheet: Int, mode: Mode, hasPage: Bool) {
        showsModeToggle = hasPage
        pageButton.isHidden = !hasPage
        tableButton.isHidden = !hasPage
        pageButton.isChosen = mode == .page
        tableButton.isChosen = mode == .table

        if tabs.count != sheetNames.count {
            tabs.forEach { $0.removeFromSuperview() }
            tabs = sheetNames.enumerated().map { index, title in
                let tab = SheetTabView(title: title, index: index)
                tab.onSelect = { [weak self] in self?.onSelectSheet?($0) }
                addSubview(tab)
                return tab
            }
        } else {
            for (tab, title) in zip(tabs, sheetNames) { tab.title = title }
        }

        // One sheet needs no chooser; the name is already in the meta line.
        let showsTabs = sheetNames.count > 1
        for (index, tab) in tabs.enumerated() {
            tab.isHidden = !showsTabs
            tab.isChosen = index == selectedSheet && mode == .table
        }

        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    /// The bar carries its own bottom margin, so a workbook with nothing to
    /// choose collapses to nothing and every other preview keeps the spacing it
    /// had before this control existed.
    override var intrinsicContentSize: NSSize {
        let content = flow(placing: false)
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: content > 0 ? content + 12 : 0
        )
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        invalidateIntrinsicContentSize()
    }

    override func layout() {
        super.layout()
        _ = flow(placing: true)
    }

    /// Measures and places in one pass, so the height reported can never
    /// disagree with what is drawn.
    @discardableResult
    private func flow(placing: Bool) -> CGFloat {
        let visible: [NSView] = (showsModeToggle ? [pageButton, tableButton] : [])
            + tabs.filter { !$0.isHidden }
        guard !visible.isEmpty else { return 0 }

        let maximumWidth = max(bounds.width, 1)
        var x: CGFloat = 0
        var y: CGFloat = 0

        for (index, view) in visible.enumerated() {
            let width = view.intrinsicContentSize.width
            if x > 0, x + width > maximumWidth {
                x = 0
                y += controlHeight + rowSpacing
            }
            if placing {
                view.frame = NSRect(x: x, y: y, width: width, height: controlHeight)
            }
            // The toggle and the tabs are separate groups, so the gap after the
            // toggle is wider than the gap between two tabs.
            let isLastToggleButton = showsModeToggle && index == 1
            x += width + (isLastToggleButton ? tabSpacing * 3 : tabSpacing)
        }
        return y + controlHeight
    }
}

// MARK: - Controls

/// A chooser in the paper idiom: wine when chosen, hairline when not.
private class PaperChip: NSView {
    var isChosen = false {
        didSet { needsDisplay = true }
    }

    var title: String = "" {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    var accent: NSColor { PaperTheme.wine }
    var font: NSFont { PaperTheme.mono(9, weight: .medium) }
    var horizontalPadding: CGFloat { 10 }

    override var isFlipped: Bool { true }

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    private var attributed: NSAttributedString {
        NSAttributedString(
            string: title,
            attributes: [
                .font: font,
                .foregroundColor: isChosen ? NSColor.white : PaperTheme.inkSoft
            ]
        )
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: (attributed.size().width + horizontalPadding * 2).rounded(), height: 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        let body = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: body, xRadius: 4, yRadius: 4)
        if isChosen {
            accent.setFill()
            path.fill()
        } else {
            PaperTheme.hairline.setStroke()
            path.lineWidth = 0.75
            path.stroke()
        }
        let text = attributed
        text.draw(at: NSPoint(
            x: (bounds.width - text.size().width) / 2,
            y: (bounds.height - text.size().height) / 2
        ))
    }

    func handleSelection() {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        handleSelection()
    }
}

private final class ModeButton: PaperChip {
    var onSelect: (() -> Void)?
    override func handleSelection() { onSelect?() }
}

private final class SheetTabView: PaperChip {
    let index: Int
    var onSelect: ((Int) -> Void)?

    /// Sheet tabs take the denim of structure rather than the wine of identity,
    /// so the mode toggle stays the louder of the two rows.
    override var accent: NSColor { PaperTheme.denim }
    override var font: NSFont { PaperTheme.serif(10.5) }
    override var horizontalPadding: CGFloat { 9 }

    init(title: String, index: Int) {
        self.index = index
        super.init(title: title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    override func handleSelection() { onSelect?(index) }
}
