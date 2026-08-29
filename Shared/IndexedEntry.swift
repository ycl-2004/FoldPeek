import Foundation

struct IndexedEntry: Identifiable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let size: Int64?
    let modificationDate: Date?
    let kind: String

    var id: String { url.path }

    var formattedSize: String {
        guard !isDirectory, let size else { return "--" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedModificationDate: String {
        guard let modificationDate else { return "--" }
        return Self.timestampFormatter.string(from: modificationDate)
    }

    /// The compact figure the index column prints, e.g. "May 24".
    var shortModificationDate: String {
        guard let modificationDate else { return "--" }
        return Self.compactDateFormatter.string(from: modificationDate)
    }

    init(url: URL, values: URLResourceValues) {
        let link = values.isSymbolicLink ?? false
        self.url = url
        name = url.lastPathComponent
        isDirectory = (values.isDirectory ?? false) && !link
        isSymbolicLink = link
        size = values.fileSize.map(Int64.init)
        modificationDate = values.contentModificationDate
        kind = link ? "Symbolic Link" : (values.localizedTypeDescription ?? "Item")
    }

    private static let timestampFormatter = makeFormatter(date: .medium, time: .short)
    private static let compactDateFormatter = makeFormatter(template: "MMMd")

    private static func makeFormatter(
        date: DateFormatter.Style,
        time: DateFormatter.Style
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = date
        formatter.timeStyle = time
        return formatter
    }

    private static func makeFormatter(template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
