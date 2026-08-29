import Foundation

/// A shared ceiling on how much of a tree one preview may materialize.
///
/// Each preview panel gets its own budget. Without it, a deep or wide
/// hierarchy could be expanded until the extension exhausts memory.
final class FolderTreeBudget {
    static let maximumTotalItems = 20_000

    private(set) var remaining: Int

    init(limit: Int = FolderTreeBudget.maximumTotalItems) {
        remaining = limit
    }

    var isExhausted: Bool { remaining <= 0 }

    func consume(_ count: Int) {
        remaining = max(0, remaining - count)
    }
}

/// One heading in the index, holding the root-level rows of a single category.
///
/// Grouping applies to the previewed folder's own contents only. Expanding a
/// folder still lists its children in the plain folders-then-names order, so a
/// deep tree never stacks headings inside headings.
final class IndexGroup {
    let category: FileCategory
    let nodes: [FolderNode]
    /// Nodes surviving the current filter — what the outline view shows.
    private(set) var visibleNodes: [FolderNode]

    init(category: FileCategory, nodes: [FolderNode]) {
        self.category = category
        self.nodes = nodes
        visibleNodes = nodes
    }

    /// Partitions already-sorted rows into headed groups, dropping the empties.
    /// The scanner's order is preserved inside each group.
    static func group(_ nodes: [FolderNode]) -> [IndexGroup] {
        var buckets: [FileCategory: [FolderNode]] = [:]
        for node in nodes {
            buckets[FileCategory.of(node.item), default: []].append(node)
        }
        return FileCategory.allCases.compactMap { category in
            guard let members = buckets[category], !members.isEmpty else { return nil }
            return IndexGroup(category: category, nodes: members)
        }
    }

    /// Narrows the group to the query and reports whether anything survived.
    @discardableResult
    func applyFilter(_ query: String) -> Bool {
        guard !query.isEmpty else {
            nodes.forEach { $0.applyFilter("") }
            visibleNodes = nodes
            return true
        }
        visibleNodes = nodes.filter { $0.applyFilter(query) }
        return !visibleNodes.isEmpty
    }
}

/// One row in the index; children are loaded only when expanded.
final class FolderNode {
    /// How many levels below the previewed folder may be opened.
    static let maximumDepth = 8

    let item: IndexedEntry
    let depth: Int

    private(set) var children: [FolderNode]?
    /// Children after the current filter — what the outline view actually shows.
    private(set) var visibleChildren: [FolderNode] = []
    private(set) var wasTruncated = false
    private(set) var loadErrorMessage: String?

    init(item: IndexedEntry, depth: Int) {
        self.item = item
        self.depth = depth
    }

    /// Directories can be opened, but never symbolic links and never past the depth cap.
    var isExpandable: Bool {
        item.isDirectory && !item.isSymbolicLink && depth < Self.maximumDepth
    }

    var isLoaded: Bool { children != nil }

    /// Reads one level of children. Repeat calls are ignored, so expanding and
    /// collapsing a folder does not re-enumerate it.
    func loadChildrenIfNeeded(budget: FolderTreeBudget) {
        guard children == nil, isExpandable else { return }

        guard !budget.isExhausted else {
            children = []
            visibleChildren = []
            loadErrorMessage = "Item limit reached."
            return
        }

        let result = DirectoryScanner.scan(item.url)
        let allowed = min(result.items.count, budget.remaining)
        budget.consume(allowed)

        let loaded = result.items.prefix(allowed).map {
            FolderNode(item: $0, depth: depth + 1)
        }
        children = loaded
        visibleChildren = loaded
        wasTruncated = result.wasTruncated || allowed < result.items.count
        loadErrorMessage = result.errorMessage
    }

    // MARK: - Filtering

    /// Narrows `visibleChildren` to the query, and reports whether this node
    /// survives it. Filtering only ever walks children that are already
    /// loaded, so searching never triggers new directory reads.
    @discardableResult
    func applyFilter(_ query: String) -> Bool {
        guard !query.isEmpty else {
            visibleChildren = children ?? []
            children?.forEach { $0.applyFilter("") }
            return true
        }

        if item.name.localizedCaseInsensitiveContains(query) {
            // A matching folder reveals everything already read beneath it.
            visibleChildren = children ?? []
            children?.forEach { $0.applyFilter("") }
            return true
        }

        visibleChildren = (children ?? []).filter { $0.applyFilter(query) }
        return !visibleChildren.isEmpty
    }

    /// The deepest level currently loaded beneath this node, relative to the root.
    var deepestLoadedDepth: Int {
        guard let children, !children.isEmpty else { return depth }
        return children.map(\.deepestLoadedDepth).max() ?? depth
    }
}
