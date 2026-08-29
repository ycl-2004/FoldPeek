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
