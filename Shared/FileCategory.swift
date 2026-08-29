import AppKit
import Foundation
import UniformTypeIdentifiers

/// What kind of thing a row is, for the purpose of grouping and colouring the
/// index.
///
/// This is a presentation concept, not a security one. Nothing here decides how
/// a file is read — `FilePreviewLoader` does that from the real content type.
/// Classification runs once per visible row, so it stays a dictionary lookup
/// over the path extension and never touches the disk.
enum FileCategory: Int, CaseIterable {
    case folder
    case symbolicLink
    case document
    case spreadsheet
    case presentation
    case image
    case video
    case audio
    case code
    case text
    case data
    case archive
    case other

    /// The heading printed above the group.
    var title: String {
        switch self {
        case .folder: return "文件夹"
        case .symbolicLink: return "符号链接"
        case .document: return "文档"
        case .spreadsheet: return "表格"
        case .presentation: return "演示"
        case .image: return "图像"
        case .video: return "视频"
        case .audio: return "音频"
        case .code: return "代码"
        case .text: return "文本"
        case .data: return "数据"
        case .archive: return "归档"
        case .other: return "其它"
        }
    }

    /// The monospaced tag beside the heading. Latin, because every other
    /// figure in this pane is set in the mono face.
    var tag: String {
        switch self {
        case .folder: return "FOLDERS"
        case .symbolicLink: return "LINKS"
        case .document: return "DOCUMENTS"
        case .spreadsheet: return "SHEETS"
        case .presentation: return "SLIDES"
        case .image: return "IMAGES"
        case .video: return "VIDEO"
        case .audio: return "AUDIO"
        case .code: return "CODE"
        case .text: return "TEXT"
        case .data: return "DATA"
        case .archive: return "ARCHIVES"
        case .other: return "OTHER"
        }
    }

    var color: NSColor { PaperTheme.Category.color(for: self) }

    /// The glyph shown when a row has no short extension to print.
    var symbol: String {
        switch self {
        case .folder: return "folder"
        case .symbolicLink: return "link"
        case .document: return "doc.text"
        case .spreadsheet: return "tablecells"
        case .presentation: return "rectangle.on.rectangle"
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .text: return "text.alignleft"
        case .data: return "curlybraces"
        case .archive: return "shippingbox"
        case .other: return "doc"
        }
    }

    // MARK: - Classification

    static func of(_ entry: IndexedEntry) -> FileCategory {
        if entry.isSymbolicLink { return .symbolicLink }
        if entry.isDirectory { return .folder }
        return of(pathExtension: entry.url.pathExtension)
    }

    static func of(pathExtension: String) -> FileCategory {
        let key = pathExtension.lowercased()
        if let known = extensions[key] { return known }

        // Anything unlisted is asked of the type system once, so a format this
        // table has never heard of still lands in a sensible group.
        guard let type = UTType(filenameExtension: key) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) { return .code }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .spreadsheet) { return .spreadsheet }
        if type.conforms(to: .presentation) { return .presentation }
        if type.conforms(to: .pdf) || type.conforms(to: .compositeContent) { return .document }
        if type.conforms(to: .text) { return .text }
        return .other
    }

    /// The extensions worth answering without consulting the type system.
    private static let extensions: [String: FileCategory] = {
        var table: [String: FileCategory] = [:]
        func add(_ category: FileCategory, _ names: [String]) {
            for name in names { table[name] = category }
        }

        add(.document, [
            "pdf", "doc", "docx", "rtf", "rtfd", "odt", "pages",
            "epub", "mobi", "azw3", "djvu", "tex", "wpd"
        ])
        add(.spreadsheet, [
            "xls", "xlsx", "xlsm", "csv", "tsv", "numbers", "ods"
        ])
        add(.presentation, [
            "ppt", "pptx", "key", "odp"
        ])
        add(.image, [
            "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tif", "tiff",
            "bmp", "svg", "ico", "icns", "psd", "ai", "raw", "cr2", "nef",
            "dng", "arw", "avif", "jfif"
        ])
        add(.video, [
            "mp4", "mov", "m4v", "avi", "mkv", "webm", "flv", "wmv", "mpg",
            "mpeg", "3gp", "prores"
        ])
        add(.audio, [
            "mp3", "wav", "aiff", "aif", "flac", "aac", "m4a", "ogg", "opus",
            "wma", "mid", "midi", "caf"
        ])
        add(.code, [
            "swift", "m", "mm", "h", "hpp", "c", "cc", "cpp", "cxx",
            "py", "rb", "js", "mjs", "cjs", "jsx", "ts", "tsx", "go", "rs",
            "java", "kt", "kts", "scala", "cs", "php", "pl", "lua", "r",
            "sh", "bash", "zsh", "fish", "ps1", "bat", "cmd",
            "html", "htm", "css", "scss", "sass", "less", "vue", "svelte",
            "sql", "dart", "ex", "exs", "erl", "hs", "clj", "vim", "el"
        ])
        add(.text, [
            "txt", "md", "markdown", "mdown", "mkd", "mdx", "rst", "org",
            "log", "text", "nfo", "readme", "license"
        ])
        add(.data, [
            "json", "yaml", "yml", "toml", "xml", "plist", "ini", "cfg",
            "conf", "env", "properties", "db", "sqlite", "sqlite3", "parquet",
            "proto", "graphql", "lock"
        ])
        add(.archive, [
            "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "dmg",
            "pkg", "iso", "jar", "war", "deb", "rpm", "zst"
        ])
        return table
    }()
}
