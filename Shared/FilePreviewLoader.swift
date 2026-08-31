import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// The rendered form of a file, or the reason no preview was produced.
enum FilePreviewContent {
    case text(String, isTruncated: Bool)
    /// A word-processing document, re-typed onto the paper surface.
    case richText(NSAttributedString, isTruncated: Bool)
    case image(NSImage, pixelWidth: Int, pixelHeight: Int)
    case pdf(PDFDocument, pageCount: Int)
    /// A single page drawn by the system for a format FoldPeek cannot read.
    case rendered(NSImage, note: String)
    /// A spreadsheet: the page image when one exists, plus the sheets as text.
    case workbook(Workbook, page: NSImage?, note: String?)
    case unavailable(String)
}

struct FilePreviewResult {
    let content: FilePreviewContent
    let byteSize: Int64?
    let typeDescription: String
}

/// Reads a bounded preview of a single regular file.
///
/// Five renderers exist, in the order they are tried: word-processing
/// documents through AppKit's own readers, PDF through PDFKit, images through
/// ImageIO at a capped pixel size, plain text as characters in a non-editable
/// text view, and — for everything left — one page drawn out of process by the
/// system thumbnail service.
///
/// Nothing here parses HTML, RTF-as-HTML, SVG, or archives by hand, no reader
/// is ever chosen by sniffing a document's own bytes, and no file is read in
/// full beyond the caps below.
enum FilePreviewLoader {
    /// Caps the characters held in memory for a text preview.
    static let maximumTextBytes = 256 * 1024
    /// Refuses to hand very large files to ImageIO at all.
    static let maximumImageFileBytes: Int64 = 64 * 1024 * 1024
    /// Bounds decoded image memory regardless of the file's real dimensions.
    static let maximumImagePixelSize: CGFloat = 2_048
    /// Refuses to open a PDF above this size; PDFKit maps the whole document.
    static let maximumPDFFileBytes: Int64 = 512 * 1024 * 1024
    /// How much of an untyped file is inspected before calling it text.
    private static let sniffByteCount = 8 * 1024

    /// What the cheap, synchronous inspection decided to do with the file.
    private enum Route {
        case done(FilePreviewContent)
        case richDocument(NSAttributedString.DocumentType)
        case systemRender
    }

    private struct Probe {
        let route: Route
        let byteSize: Int64?
        let typeDescription: String
    }

    static func load(url: URL) async -> FilePreviewResult {
        let probe = await Task.detached(priority: .userInitiated) { inspect(url: url) }.value

        switch probe.route {
        case let .done(content):
            return result(content, probe)

        case let .richDocument(documentType):
            if let document = await RichDocumentReader.read(
                url: url,
                type: documentType,
                byteSize: probe.byteSize
            ) {
                return result(.richText(document.text, isTruncated: document.isTruncated), probe)
            }
            // A reader that declined leaves the file to the system, which may
            // still be able to draw it.
            return result(await systemRendering(url: url, probe: probe), probe)

        case .systemRender:
            return result(await systemRendering(url: url, probe: probe), probe)
        }
    }

    private static func result(_ content: FilePreviewContent, _ probe: Probe) -> FilePreviewResult {
        FilePreviewResult(
            content: content,
            byteSize: probe.byteSize,
            typeDescription: probe.typeDescription
        )
    }

    /// Two ways to get a picture of a page FoldPeek cannot typeset, tried in
    /// order of how much has to go right.
    ///
    /// The container's own embedded preview comes first: it is already an
    /// image, it is read in this process, and it works regardless of what the
    /// sandbox will let this extension hand to another process. Only when a
    /// file carries no such picture is the system thumbnail service asked —
    /// which is the path that fails when Quick Look's grant cannot be re-vended.
    private static func systemRendering(url: URL, probe: Probe) async -> FilePreviewContent {
        var page: NSImage?
        var note: String?

        if ContainerPreviewReader.handles(pathExtension: url.pathExtension) {
            page = await Task.detached(priority: .userInitiated) {
                ContainerPreviewReader.embeddedPreview(at: url)
            }.value
            if page != nil { note = "内嵌预览 · 首页" }
        }
        if page == nil, let image = await SystemPageRenderer.render(url: url, byteSize: probe.byteSize) {
            page = image
            note = "系统渲染 · 首页"
        }

        // A workbook's page image shows one sheet of however many it has, so
        // the sheets are read as well and the pane offers both.
        if WorkbookReader.handles(pathExtension: url.pathExtension) {
            let workbook = await Task.detached(priority: .userInitiated) {
                WorkbookReader.read(at: url)
            }.value
            if let workbook {
                return .workbook(workbook, page: page, note: note)
            }
        }

        if let page, let note {
            return .rendered(page, note: note)
        }

        PreviewLog.stage("allPathsFailed", outcome: url.pathExtension.lowercased())
        return .unavailable(
            "无法取得此文件的页面图像。\n它没有内嵌预览，系统渲染服务也未能返回结果。"
        )
    }

    // MARK: - Routing

    private static func inspect(url: URL) -> Probe {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentTypeKey,
            .localizedTypeDescriptionKey
        ]

        guard let values = try? url.resourceValues(forKeys: keys) else {
            return Probe(
                route: .done(.unavailable("此条目无法读取。")),
                byteSize: nil,
                typeDescription: "Item"
            )
        }

        let typeDescription = values.localizedTypeDescription ?? "Item"
        let byteSize = values.fileSize.map(Int64.init)

        // Symbolic links are listed but never followed, here as well as in the tree.
        if values.isSymbolicLink == true {
            return Probe(
                route: .done(.unavailable("不跟随符号链接。")),
                byteSize: byteSize,
                typeDescription: "Symbolic Link"
            )
        }

        // Rejects directories, sockets, FIFOs, and device nodes.
        guard values.isRegularFile == true else {
            return Probe(
                route: .done(.unavailable("只有普通文件可以预览。")),
                byteSize: byteSize,
                typeDescription: typeDescription
            )
        }

        let contentType = values.contentType

        // Word-processing formats are matched before the text branch on
        // purpose: RTF conforms to `public.text`, and showing its markup as
        // source is not what anyone means by previewing a document.
        if let documentType = RichDocumentReader.documentType(forPathExtension: url.pathExtension) {
            return Probe(
                route: .richDocument(documentType),
                byteSize: byteSize,
                typeDescription: typeDescription
            )
        }

        if let contentType, contentType.conforms(to: .pdf) {
            return Probe(
                route: .done(loadPDF(url: url, byteSize: byteSize)),
                byteSize: byteSize,
                typeDescription: typeDescription
            )
        }

        if let contentType, contentType.conforms(to: .image) {
            return Probe(
                route: .done(loadImage(url: url, byteSize: byteSize)),
                byteSize: byteSize,
                typeDescription: typeDescription
            )
        }

        if let contentType, contentType.conforms(to: .text) {
            return Probe(
                route: .done(readTextPreview(at: url)),
                byteSize: byteSize,
                typeDescription: typeDescription
            )
        }

        // Files without a text UTType (dotfiles, extension-less scripts) are
        // shown only when a byte sniff says they are plainly textual.
        if looksTextual(url: url) {
            return Probe(
                route: .done(readTextPreview(at: url)),
                byteSize: byteSize,
                typeDescription: typeDescription
            )
        }

        return Probe(route: .systemRender, byteSize: byteSize, typeDescription: typeDescription)
    }

    // MARK: - Text

    private static func readTextPreview(at url: URL) -> FilePreviewContent {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return .unavailable("此文件无法打开。")
        }
        defer { try? handle.close() }

        // Reads one byte past the cap purely to detect truncation.
        guard let data = try? handle.read(upToCount: maximumTextBytes + 1) else {
            return .unavailable("此文件无法读取。")
        }

        let isTruncated = data.count > maximumTextBytes
        let bounded = isTruncated ? data.prefix(maximumTextBytes) : data

        // Decoding is lossy on purpose: invalid bytes become U+FFFD rather
        // than failing, and no encoding sniffing logic is involved.
        let text = String(decoding: bounded, as: UTF8.self)
        if text.isEmpty {
            return .unavailable("此文件为空。")
        }
        return .text(text, isTruncated: isTruncated)
    }

    /// True when the leading bytes contain no NUL and decode as mostly printable text.
    private static func looksTextual(url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: sniffByteCount), !data.isEmpty else {
            return false
        }
        if data.contains(0) { return false }

        let printable = data.reduce(into: 0) { count, byte in
            // Tab, newline, carriage return, printable ASCII, or UTF-8 continuation.
            if byte == 9 || byte == 10 || byte == 13 || (byte >= 32 && byte < 127) || byte >= 128 {
                count += 1
            }
        }
        return Double(printable) / Double(data.count) > 0.9
    }

    // MARK: - PDF

    private static func loadPDF(url: URL, byteSize: Int64?) -> FilePreviewContent {
        if let byteSize, byteSize > maximumPDFFileBytes {
            return .unavailable("此 PDF 过大，无法安全预览。")
        }
        guard let document = PDFDocument(url: url) else {
            return .unavailable("此 PDF 无法读取。\n文件可能已损坏。")
        }
        // An encrypted document opens, but every page draws blank until it is
        // unlocked, and FoldPeek never asks for a password.
        if document.isLocked {
            return .unavailable("此 PDF 已加密。\nFoldPeek 不会请求密码。")
        }
        guard document.pageCount > 0 else {
            return .unavailable("此 PDF 没有可显示的页面。")
        }
        return .pdf(document, pageCount: document.pageCount)
    }

    // MARK: - Image

    private static func loadImage(url: URL, byteSize: Int64?) -> FilePreviewContent {
        if let byteSize, byteSize > maximumImageFileBytes {
            return .unavailable("此图片过大，无法安全预览。")
        }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return .unavailable("此图片无法读取。")
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelWidth = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let pixelHeight = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0

        // Thumbnail decoding caps memory no matter how large the source image claims to be.
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumImagePixelSize,
            kCGImageSourceShouldCache: false
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return .unavailable("此图片无法解码。")
        }

        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        return .image(image, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }
}
