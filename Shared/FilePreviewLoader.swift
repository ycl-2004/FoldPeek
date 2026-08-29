import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The rendered form of a file, or the reason no preview was produced.
enum FilePreviewContent {
    case text(String, isTruncated: Bool)
    case image(NSImage, pixelWidth: Int, pixelHeight: Int)
    case unavailable(String)
}

struct FilePreviewResult {
    let content: FilePreviewContent
    let byteSize: Int64?
    let typeDescription: String
}

/// Reads a bounded preview of a single regular file.
///
/// Only two renderers exist, and both are deliberately inert:
/// plain text is shown as characters in a non-editable text view, and images
/// are decoded through ImageIO at a capped pixel size. Nothing here parses
/// HTML, Markdown, RTF, SVG, archives, or any other active content, and no
/// file is ever read in full.
enum FilePreviewLoader {
    /// Caps the characters held in memory for a text preview.
    static let maximumTextBytes = 256 * 1024
    /// Refuses to hand very large files to ImageIO at all.
    static let maximumImageFileBytes: Int64 = 64 * 1024 * 1024
    /// Bounds decoded image memory regardless of the file's real dimensions.
    static let maximumImagePixelSize: CGFloat = 2_048
    /// How much of an untyped file is inspected before calling it text.
    private static let sniffByteCount = 8 * 1024

    static func load(url: URL) -> FilePreviewResult {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentTypeKey,
            .localizedTypeDescriptionKey
        ]

        guard let values = try? url.resourceValues(forKeys: keys) else {
            return FilePreviewResult(
                content: .unavailable("This item could not be read."),
                byteSize: nil,
                typeDescription: "Item"
            )
        }

        let typeDescription = values.localizedTypeDescription ?? "Item"
        let byteSize = values.fileSize.map(Int64.init)

        // Symbolic links are listed but never followed, here as well as in the tree.
        if values.isSymbolicLink == true {
            return FilePreviewResult(
                content: .unavailable("Symbolic links are not followed."),
                byteSize: byteSize,
                typeDescription: "Symbolic Link"
            )
        }

        // Rejects directories, sockets, FIFOs, and device nodes.
        guard values.isRegularFile == true else {
            return FilePreviewResult(
                content: .unavailable("Only regular files can be previewed."),
                byteSize: byteSize,
                typeDescription: typeDescription
            )
        }

        let contentType = values.contentType

        if let contentType, contentType.conforms(to: .image) {
            return FilePreviewResult(
                content: loadImage(url: url, byteSize: byteSize),
                byteSize: byteSize,
                typeDescription: typeDescription
            )
        }

        if let contentType, contentType.conforms(to: .text) {
            return FilePreviewResult(
                content: readTextPreview(at: url),
                byteSize: byteSize,
                typeDescription: typeDescription
            )
        }

        // Files without a text UTType (dotfiles, extension-less scripts) are
        // shown only when a byte sniff says they are plainly textual.
        if looksTextual(url: url) {
            return FilePreviewResult(
                content: readTextPreview(at: url),
                byteSize: byteSize,
                typeDescription: typeDescription
            )
        }

        return FilePreviewResult(
            content: .unavailable("No preview available for this file type."),
            byteSize: byteSize,
            typeDescription: typeDescription
        )
    }

    // MARK: - Text

    private static func readTextPreview(at url: URL) -> FilePreviewContent {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return .unavailable("This file could not be opened.")
        }
        defer { try? handle.close() }

        // Reads one byte past the cap purely to detect truncation.
        guard let data = try? handle.read(upToCount: maximumTextBytes + 1) else {
            return .unavailable("This file could not be read.")
        }

        let isTruncated = data.count > maximumTextBytes
        let bounded = isTruncated ? data.prefix(maximumTextBytes) : data

        // Decoding is lossy on purpose: invalid bytes become U+FFFD rather
        // than failing, and no encoding sniffing logic is involved.
        let text = String(decoding: bounded, as: UTF8.self)
        if text.isEmpty {
            return .unavailable("This file is empty.")
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

    // MARK: - Image

    private static func loadImage(url: URL, byteSize: Int64?) -> FilePreviewContent {
        if let byteSize, byteSize > maximumImageFileBytes {
            return .unavailable("Image is too large to preview safely.")
        }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return .unavailable("This image could not be read.")
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
            return .unavailable("This image could not be decoded.")
        }

        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        return .image(image, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }
}
