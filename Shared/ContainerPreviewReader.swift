import AppKit
import Foundation
import ImageIO

/// Recovers the preview image a document container already carries.
///
/// Pages, Keynote, Numbers, and some Office files are ZIP containers that store
/// a rendered picture of their own first page. Reading that picture needs no
/// document parser and no help from any other process — which matters, because
/// the system thumbnail service cannot be handed a file that a sandboxed
/// extension reached through Quick Look's own grant.
///
/// This reader is deliberately narrow. It asks `ZipArchive` for entries by
/// exact name, inflates at most one of them, and hands the result to ImageIO.
/// It never writes anything to disk and never follows a path stored inside the
/// file.
enum ContainerPreviewReader {
    /// Entry names worth looking for, best picture first.
    private static let candidates = [
        // iWork — a full-size render of page one, almost always stored uncompressed.
        "preview.jpg",
        "QuickLook/Thumbnail.jpg",
        "preview-web.jpg",
        // Office Open XML — present only when the authoring app chose to save it.
        "docProps/thumbnail.jpeg",
        "docProps/thumbnail.jpg",
        "docProps/thumbnail.png"
    ]

    /// The containers worth opening. Anything else is not a ZIP document.
    private static let extensions: Set<String> = [
        "pages", "key", "numbers", "pptx", "docx", "xlsx", "ppsx", "odp", "ods", "odt"
    ]

    static func handles(pathExtension: String) -> Bool {
        extensions.contains(pathExtension.lowercased())
    }

    static func embeddedPreview(at url: URL) -> NSImage? {
        guard let archive = ZipArchive(url: url) else { return nil }
        for name in candidates {
            guard let data = archive.data(for: name) else { continue }
            if let image = decode(data) { return image }
        }
        return nil
    }

    // MARK: - Decoding

    /// The recovered bytes are an image and nothing else, so they go through
    /// the same capped ImageIO path as any other picture.
    private static func decode(_ data: Data) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: FilePreviewLoader.maximumImagePixelSize,
            kCGImageSourceShouldCache: false
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

}
