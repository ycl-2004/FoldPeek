import Foundation

struct DirectorySnapshot: Sendable {
    let items: [IndexedEntry]
    let wasTruncated: Bool
    let errorMessage: String?
}

enum DirectoryScanner {
    /// Bounds Quick Look memory use for unusually large directories.
    static let maximumItemCount = 2_000

    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .localizedTypeDescriptionKey
    ]

    static func scan(_ folderURL: URL) -> DirectorySnapshot {
        var snapshot = DirectorySnapshot(items: [], wasTruncated: false, errorMessage: nil)
        var coordinatorError: NSError?

        NSFileCoordinator().coordinate(
            readingItemAt: folderURL,
            options: [.withoutChanges],
            error: &coordinatorError
        ) { readURL in
            snapshot = scanSingleLevel(readURL)
        }

        if let coordinatorError, snapshot.errorMessage == nil {
            return DirectorySnapshot(
                items: snapshot.items,
                wasTruncated: snapshot.wasTruncated,
                errorMessage: coordinatorError.localizedDescription
            )
        }

        return snapshot
    }

    private static func scanSingleLevel(_ folderURL: URL) -> DirectorySnapshot {
        var enumerationError: Error?
        let options: FileManager.DirectoryEnumerationOptions = [
            .skipsHiddenFiles,
            .skipsPackageDescendants,
            .skipsSubdirectoryDescendants
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: options,
            errorHandler: { _, error in
                if enumerationError == nil { enumerationError = error }
                return true
            }
        ) else {
            return DirectorySnapshot(
                items: [],
                wasTruncated: false,
                errorMessage: "The folder could not be read."
            )
        }

        var items: [IndexedEntry] = []
        var wasTruncated = false

        for case let url as URL in enumerator {
            if items.count >= maximumItemCount {
                wasTruncated = true
                break
            }

            guard let values = try? url.resourceValues(forKeys: resourceKeys) else { continue }
            items.append(IndexedEntry(url: url, values: values))
        }

        items.sort { left, right in
            if left.isDirectory != right.isDirectory {
                return left.isDirectory && !right.isDirectory
            }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }

        return DirectorySnapshot(
            items: items,
            wasTruncated: wasTruncated,
            errorMessage: enumerationError?.localizedDescription
        )
    }
}
