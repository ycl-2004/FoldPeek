import AppKit
import QuickLookUI

final class FoldPeekPreviewController: NSViewController, QLPreviewingController {
    private static let indexColumn = NSUserInterfaceItemIdentifier("index")

    // Index pane
    private let indexPane = NSView()
    private let identityRule = NSView()
    private let identityLabel = NSTextField(labelWithString: "FoldPeek")
    private let pathLabel = NSTextField(labelWithString: "")
    private let sectionNumber = NSTextField(labelWithString: "01")
    private let sectionTitle = NSTextField(labelWithString: "Index")
    private let sectionCount = NSTextField(labelWithString: "")
    private let searchIcon = NSImageView()
    private let searchField = NSTextField(string: "")
    private let searchRule = NSView()
    private let outlineView = IndexOutlineView()
    private let outlineScrollView = NSScrollView()
    private let footerRule = NSView()
    private let footerLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(wrappingLabelWithString: "此文件夹为空。")

    // Content pane
    private let splitView = DiamondSplitView()
    private let previewPane = PreviewPaneView()

    private var rootNodes: [FolderNode] = []
    private var visibleRootNodes: [FolderNode] = []
    private var budget = FolderTreeBudget()
    private var previewTask: Task<Void, Never>?
    private var filterText = ""
    private var budgetNote: String?

    /// Held for the lifetime of the panel: children and file contents are read
    /// lazily, long after the initial load, so access cannot be released early.
    private var scopedURL: URL?
    private var didStartScope = false

    private var didSetInitialSplitPosition = false

    override var preferredContentSize: NSSize {
        get { NSSize(width: 1_180, height: 700) }
        set { super.preferredContentSize = newValue }
    }

    deinit {
        previewTask?.cancel()
        if didStartScope {
            scopedURL?.stopAccessingSecurityScopedResource()
        }
    }

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))
        view.wantsLayer = true
        view.layer?.backgroundColor = PaperTheme.cream.cgColor
        configureIndexPane()
        configureLayout()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard !didSetInitialSplitPosition, splitView.bounds.width > 0 else { return }
        didSetInitialSplitPosition = true
        splitView.setPosition(splitView.bounds.width * 0.44, ofDividerAt: 0)
    }

    // MARK: - Quick Look

    func preparePreviewOfFile(at url: URL) async throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw PreviewError.notDirectory
        }

        releaseScopedAccess()
        let folderURL = url.standardizedFileURL
        didStartScope = folderURL.startAccessingSecurityScopedResource()
        scopedURL = folderURL

        let loadResult = await Task.detached(priority: .userInitiated) {
            DirectoryScanner.scan(folderURL)
        }.value

        await MainActor.run {
            budget = FolderTreeBudget()
            budget.consume(loadResult.items.count)
            rootNodes = loadResult.items.map { FolderNode(item: $0, depth: 0) }
            visibleRootNodes = rootNodes
            filterText = ""
            searchField.stringValue = ""
            budgetNote = Self.note(for: loadResult)

            pathLabel.stringValue = (folderURL.path as NSString).abbreviatingWithTildeInPath
            sectionCount.stringValue = "\(loadResult.items.count)"

            emptyLabel.stringValue = loadResult.errorMessage ?? "此文件夹为空。"
            emptyLabel.isHidden = !rootNodes.isEmpty
            outlineView.isHidden = rootNodes.isEmpty
            outlineView.reloadData()
            updateFooter()
            previewPane.showEmptySelection()
        }
    }

    private func releaseScopedAccess() {
        if didStartScope {
            scopedURL?.stopAccessingSecurityScopedResource()
        }
        didStartScope = false
        scopedURL = nil
    }

    private static func note(for result: DirectorySnapshot) -> String? {
        if result.wasTruncated {
            return "capped at \(DirectoryScanner.maximumItemCount)"
        }
        if result.errorMessage != nil, !result.items.isEmpty {
            return "some items unreadable"
        }
        return nil
    }

    // MARK: - Filtering

    private func applyFilter() {
        if filterText.isEmpty {
            rootNodes.forEach { $0.applyFilter("") }
            visibleRootNodes = rootNodes
        } else {
            visibleRootNodes = rootNodes.filter { $0.applyFilter(filterText) }
        }

        outlineView.reloadData()
        if !filterText.isEmpty {
            expandMatches(in: visibleRootNodes)
        }
        emptyLabel.isHidden = !visibleRootNodes.isEmpty || rootNodes.isEmpty
        if !rootNodes.isEmpty {
            emptyLabel.stringValue = visibleRootNodes.isEmpty ? "没有匹配的条目。" : "此文件夹为空。"
            outlineView.isHidden = visibleRootNodes.isEmpty
        }
        updateFooter()
    }

    /// Opens the folders that survived the filter. Every node here is already
    /// loaded, so expanding cannot pull in new directories.
    private func expandMatches(in nodes: [FolderNode]) {
        for node in nodes where !node.visibleChildren.isEmpty {
            outlineView.expandItem(node)
            expandMatches(in: node.visibleChildren)
        }
    }

    private func updateFooter() {
        let folders = visibleRootNodes.filter(\.item.isDirectory).count
        let files = visibleRootNodes.count - folders
        let deepest = rootNodes.map(\.deepestLoadedDepth).max() ?? 0

        var parts = [
            "\(folders) folder\(folders == 1 ? "" : "s")",
            "\(files) file\(files == 1 ? "" : "s")",
            "depth \(deepest)/\(FolderNode.maximumDepth)"
        ]
        if let budgetNote { parts.append(budgetNote) }
        footerLabel.stringValue = parts.joined(separator: "  ·  ")
    }

    // MARK: - Selection

    /// A click anywhere on a folder row opens or closes it. The disclosure
    /// triangle is a hint, not the only target — hitting a 12 pt triangle to
    /// walk a tree is needless precision work.
    @objc private func handleIndexClick() {
        let row = outlineView.clickedRow
        guard row >= 0,
              let node = outlineView.item(atRow: row) as? FolderNode,
              node.item.isDirectory,
              !node.item.isSymbolicLink
        else { return }

        // AppKit has already toggled if the click landed on the triangle;
        // toggling again here would undo it.
        if let event = NSApp.currentEvent {
            let point = outlineView.convert(event.locationInWindow, from: nil)
            if outlineView.frameOfOutlineCell(atRow: row).contains(point) { return }
        }

        if outlineView.isItemExpanded(node) {
            outlineView.collapseItem(node)
        } else {
            outlineView.expandItem(node)
        }
        // The row may already have been selected, in which case no selection
        // notification fires and the content pane would keep a stale state.
        updatePreviewForSelection()
    }

    private func updatePreviewForSelection() {
        previewTask?.cancel()

        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FolderNode else {
            previewPane.showEmptySelection()
            return
        }

        if node.item.isDirectory {
            previewPane.showFolder(
                node.item,
                childCount: node.children?.count,
                isExpanded: outlineView.isItemExpanded(node)
            )
            return
        }

        let item = node.item
        previewPane.showLoading()
        previewTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                FilePreviewLoader.load(url: item.url)
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.outlineView.selectedRow == row else { return }
                self.previewPane.showFile(item, result: result)
            }
        }
    }

    // MARK: - Index pane

    private func configureIndexPane() {
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(handleIndexClick)
        outlineView.headerView = nil
        outlineView.style = .plain
        outlineView.backgroundColor = PaperTheme.cream
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.gridStyleMask = []
        outlineView.allowsMultipleSelection = false
        outlineView.rowHeight = 34
        outlineView.intercellSpacing = NSSize(width: 0, height: 0)
        outlineView.indentationPerLevel = 16
        outlineView.autoresizesOutlineColumn = false
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let column = NSTableColumn(identifier: Self.indexColumn)
        column.resizingMask = .autoresizingMask
        column.minWidth = 200
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
    }

    private func configureLayout() {
        indexPane.translatesAutoresizingMaskIntoConstraints = false
        indexPane.wantsLayer = true
        indexPane.layer?.backgroundColor = PaperTheme.cream.cgColor

        identityRule.translatesAutoresizingMaskIntoConstraints = false
        identityRule.wantsLayer = true
        identityRule.layer?.backgroundColor = PaperTheme.wine.cgColor

        identityLabel.translatesAutoresizingMaskIntoConstraints = false
        identityLabel.font = PaperTheme.serif(26)
        identityLabel.textColor = PaperTheme.ink

        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = PaperTheme.mono(10)
        pathLabel.textColor = PaperTheme.inkSoft
        pathLabel.lineBreakMode = .byTruncatingMiddle

        sectionNumber.translatesAutoresizingMaskIntoConstraints = false
        sectionNumber.font = PaperTheme.serifItalic(14)
        sectionNumber.textColor = PaperTheme.wine

        sectionTitle.translatesAutoresizingMaskIntoConstraints = false
        sectionTitle.font = PaperTheme.serif(14)
        sectionTitle.textColor = PaperTheme.ink

        sectionCount.translatesAutoresizingMaskIntoConstraints = false
        sectionCount.font = PaperTheme.mono(10)
        sectionCount.textColor = PaperTheme.inkFaint
        sectionCount.alignment = .right

        configureSearchField()

        for rule in [searchRule, footerRule] {
            rule.translatesAutoresizingMaskIntoConstraints = false
            rule.wantsLayer = true
            rule.layer?.backgroundColor = PaperTheme.hairline.cgColor
        }

        outlineScrollView.translatesAutoresizingMaskIntoConstraints = false
        outlineScrollView.documentView = outlineView
        outlineScrollView.hasVerticalScroller = true
        outlineScrollView.autohidesScrollers = true
        outlineScrollView.borderType = .noBorder
        outlineScrollView.drawsBackground = false

        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.font = PaperTheme.mono(9)
        footerLabel.textColor = PaperTheme.inkFaint

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.alignment = .center
        emptyLabel.font = PaperTheme.serif(12)
        emptyLabel.textColor = PaperTheme.inkSoft
        emptyLabel.isHidden = true

        for subview in [
            identityRule, identityLabel, pathLabel,
            sectionNumber, sectionTitle, sectionCount,
            searchIcon, searchField, searchRule,
            outlineScrollView, footerRule, footerLabel, emptyLabel
        ] {
            indexPane.addSubview(subview)
        }

        // An Auto Layout split view positions its arranged subviews with
        // constraints; leaving the autoresizing mask on would pin each one to
        // its current frame and snap the divider back on every drag.
        previewPane.translatesAutoresizingMaskIntoConstraints = false
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.addArrangedSubview(indexPane)
        splitView.addArrangedSubview(previewPane)
        splitView.setHoldingPriority(NSLayoutConstraint.Priority(250), forSubviewAt: 0)
        splitView.setHoldingPriority(NSLayoutConstraint.Priority(251), forSubviewAt: 1)
        view.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: view.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            indexPane.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
            previewPane.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),

            identityRule.topAnchor.constraint(equalTo: indexPane.topAnchor, constant: 26),
            identityRule.leadingAnchor.constraint(equalTo: indexPane.leadingAnchor, constant: 24),
            identityRule.widthAnchor.constraint(equalToConstant: 3),
            identityRule.bottomAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 2),

            identityLabel.topAnchor.constraint(equalTo: indexPane.topAnchor, constant: 22),
            identityLabel.leadingAnchor.constraint(equalTo: identityRule.trailingAnchor, constant: 12),
            identityLabel.trailingAnchor.constraint(lessThanOrEqualTo: indexPane.trailingAnchor, constant: -24),

            pathLabel.topAnchor.constraint(equalTo: identityLabel.bottomAnchor, constant: 2),
            pathLabel.leadingAnchor.constraint(equalTo: identityLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: indexPane.trailingAnchor, constant: -24),

            sectionNumber.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 24),
            sectionNumber.leadingAnchor.constraint(equalTo: indexPane.leadingAnchor, constant: 24),

            sectionTitle.centerYAnchor.constraint(equalTo: sectionNumber.centerYAnchor),
            sectionTitle.leadingAnchor.constraint(equalTo: sectionNumber.trailingAnchor, constant: 14),

            sectionCount.centerYAnchor.constraint(equalTo: sectionNumber.centerYAnchor),
            sectionCount.trailingAnchor.constraint(equalTo: indexPane.trailingAnchor, constant: -24),

            searchIcon.topAnchor.constraint(equalTo: sectionNumber.bottomAnchor, constant: 16),
            searchIcon.leadingAnchor.constraint(equalTo: indexPane.leadingAnchor, constant: 25),
            searchIcon.widthAnchor.constraint(equalToConstant: 13),

            searchField.centerYAnchor.constraint(equalTo: searchIcon.centerYAnchor),
            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 9),
            searchField.trailingAnchor.constraint(equalTo: indexPane.trailingAnchor, constant: -24),

            searchRule.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 9),
            searchRule.leadingAnchor.constraint(equalTo: indexPane.leadingAnchor, constant: 24),
            searchRule.trailingAnchor.constraint(equalTo: indexPane.trailingAnchor, constant: -24),
            searchRule.heightAnchor.constraint(equalToConstant: 1),

            outlineScrollView.topAnchor.constraint(equalTo: searchRule.bottomAnchor, constant: 6),
            outlineScrollView.leadingAnchor.constraint(equalTo: indexPane.leadingAnchor, constant: 10),
            outlineScrollView.trailingAnchor.constraint(equalTo: indexPane.trailingAnchor, constant: -10),
            outlineScrollView.bottomAnchor.constraint(equalTo: footerRule.topAnchor, constant: -6),

            footerRule.leadingAnchor.constraint(equalTo: indexPane.leadingAnchor, constant: 24),
            footerRule.trailingAnchor.constraint(equalTo: indexPane.trailingAnchor, constant: -24),
            footerRule.heightAnchor.constraint(equalToConstant: 1),
            footerRule.bottomAnchor.constraint(equalTo: footerLabel.topAnchor, constant: -12),

            footerLabel.leadingAnchor.constraint(equalTo: indexPane.leadingAnchor, constant: 24),
            footerLabel.trailingAnchor.constraint(equalTo: indexPane.trailingAnchor, constant: -24),
            footerLabel.bottomAnchor.constraint(equalTo: indexPane.bottomAnchor, constant: -18),

            emptyLabel.centerXAnchor.constraint(equalTo: outlineScrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: outlineScrollView.centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 260)
        ])
    }

    private func configureSearchField() {
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
        searchIcon.contentTintColor = PaperTheme.inkFaint
        searchIcon.imageScaling = .scaleProportionallyDown

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = PaperTheme.serif(12)
        searchField.textColor = PaperTheme.ink
        searchField.placeholderString = "搜索 / Filter"
        searchField.delegate = self
        searchField.cell?.sendsActionOnEndEditing = false
    }
}

// MARK: - Search

extension FoldPeekPreviewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) === searchField else { return }
        filterText = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        applyFilter()
    }
}

// MARK: - Index list

extension FoldPeekPreviewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? FolderNode else { return visibleRootNodes.count }
        return node.visibleChildren.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? FolderNode else { return visibleRootNodes[index] }
        return node.visibleChildren[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? FolderNode else { return false }
        // Before loading, any eligible directory offers a triangle; afterwards
        // the real child count decides, so empty folders stop offering one.
        return node.isLoaded ? !node.visibleChildren.isEmpty : node.isExpandable
    }

    func outlineViewItemWillExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FolderNode else { return }
        node.loadChildrenIfNeeded(budget: budget)
        node.applyFilter(filterText)
        if budget.isExhausted {
            budgetNote = "stopped at \(FolderTreeBudget.maximumTotalItems)"
        }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        reloadGlyph(from: notification)
        updateFooter()
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        reloadGlyph(from: notification)
        updateFooter()
    }

    /// With the triangles gone, the folder glyph is the open/closed cue, so
    /// the row has to be redrawn whenever that state changes.
    private func reloadGlyph(from notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FolderNode else { return }
        let row = outlineView.row(forItem: node)
        guard row >= 0 else { return }
        outlineView.reloadData(forRowIndexes: [row], columnIndexes: [0])
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        updatePreviewForSelection()
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let rowView = IndexRowView()
        if let node = item as? FolderNode {
            rowView.showsTopSeparator = isFirstRootFile(node)
        }
        return rowView
    }

    /// The hairline that divides the folder group from the file group.
    private func isFirstRootFile(_ node: FolderNode) -> Bool {
        guard !node.item.isDirectory,
              let index = visibleRootNodes.firstIndex(where: { $0 === node }),
              index > 0
        else { return false }
        return visibleRootNodes[index - 1].item.isDirectory
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let node = item as? FolderNode else { return nil }
        let entry = node.item

        let cell = (outlineView.makeView(withIdentifier: Self.indexColumn, owner: self) as? IndexCellView)
            ?? {
                let created = IndexCellView()
                created.identifier = Self.indexColumn
                return created
            }()

        cell.nameLabel.stringValue = entry.name

        if entry.isSymbolicLink {
            cell.showFolder(symbol: "link", tint: PaperTheme.inkFaint)
            cell.trailingLabel.stringValue = entry.shortModificationDate
        } else if entry.isDirectory {
            let isOpen = outlineView.isItemExpanded(node)
            cell.showFolder(symbol: isOpen ? "folder.fill" : "folder", tint: PaperTheme.denim)
            cell.trailingLabel.stringValue = entry.shortModificationDate
        } else {
            cell.showType(Self.typeMark(for: entry))
            cell.trailingLabel.stringValue = entry.formattedSize
        }

        return cell
    }

    private static func typeMark(for item: IndexedEntry) -> String {
        let ext = item.url.pathExtension.uppercased()
        guard !ext.isEmpty, ext.count <= 4 else { return "•" }
        return ext
    }
}

private enum PreviewError: LocalizedError {
    case notDirectory

    var errorDescription: String? {
        "FoldPeek only previews folders directly, not symbolic links."
    }
}
