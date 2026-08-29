import AppKit
import Foundation

/// Reads word-processing documents through AppKit's own readers and re-types
/// the result onto the paper surface.
///
/// FoldPeek does not parse these formats itself. It hands the file to the
/// reader macOS already ships, then throws away everything the document says
/// about its own appearance: fonts become the project's faces, colours are
/// forced back to something readable on cream paper, and link attributes are
/// stripped so no destination is ever clickable.
enum RichDocumentReader {
    /// Whole-file readers hold the document in memory, so the cap is the file.
    static let maximumFileBytes: Int64 = 32 * 1024 * 1024
    /// Caps the characters laid out, the way Markdown rendering is capped.
    static let maximumCharacters = 400_000

    /// Extension → the exact reader AppKit must use.
    ///
    /// The document type is always stated and never inferred. Letting
    /// `NSAttributedString` sniff the bytes lets it fall into the HTML reader,
    /// which is WebKit-backed and would load remote resources — the one path in
    /// this file that could reach the network.
    private static let readers: [String: NSAttributedString.DocumentType] = [
        "rtf": .rtf,
        "doc": .docFormat,
        "docx": .officeOpenXML,
        "odt": .openDocument
    ]

    static func documentType(forPathExtension pathExtension: String) -> NSAttributedString.DocumentType? {
        readers[pathExtension.lowercased()]
    }

    /// AppKit's document readers are documented as main-thread work, so this is
    /// bounded by file size rather than pushed onto a background queue.
    @MainActor
    static func read(
        url: URL,
        type: NSAttributedString.DocumentType,
        byteSize: Int64?
    ) -> (text: NSAttributedString, isTruncated: Bool)? {
        if let byteSize, byteSize > maximumFileBytes { return nil }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: type
        ]
        guard let document = try? NSAttributedString(url: url, options: options, documentAttributes: nil),
              document.length > 0
        else { return nil }

        let isTruncated = document.length > maximumCharacters
        let bounded = isTruncated
            ? document.attributedSubstring(from: NSRange(location: 0, length: maximumCharacters))
            : document

        let restyled = restyle(bounded)
        guard restyled.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        return (restyled, isTruncated)
    }

    // MARK: - Re-typing

    private static func restyle(_ source: NSAttributedString) -> NSAttributedString {
        let output = NSMutableAttributedString(attributedString: source)
        let whole = NSRange(location: 0, length: output.length)

        // A document's own link destinations are never made clickable here,
        // matching the Markdown renderer.
        output.removeAttribute(.link, range: whole)
        output.removeAttribute(.toolTip, range: whole)
        output.removeAttribute(.cursor, range: whole)

        // Ranges are collected first: re-attributing a string mid-enumeration
        // invalidates the run the enumeration is standing on.
        var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
        output.enumerateAttributes(in: whole, options: []) { attributes, range, _ in
            runs.append((range, attributes))
        }

        for (range, attributes) in runs {
            if let attachment = attributes[.attachment] as? NSTextAttachment {
                bound(attachment)
            }
            output.addAttribute(
                .font,
                value: paperFont(matching: attributes[.font] as? NSFont),
                range: range
            )
            output.addAttribute(
                .foregroundColor,
                value: readableInk(attributes[.foregroundColor] as? NSColor),
                range: range
            )
        }

        return output
    }

    /// Keeps the document's structure — bold, italic, monospace, relative size —
    /// and drops its typeface for the project's own.
    private static func paperFont(matching font: NSFont?) -> NSFont {
        guard let font else { return PaperTheme.serif(12) }

        // Very large display type and near-invisible fine print both break the
        // reading measure, so the document's scale is clamped, not obeyed.
        let size = min(max(font.pointSize, 9), 28)
        let traits = font.fontDescriptor.symbolicTraits
        if traits.contains(.monoSpace) {
            return PaperTheme.mono(size, weight: traits.contains(.bold) ? .semibold : .regular)
        }

        var wanted: NSFontDescriptor.SymbolicTraits = []
        if traits.contains(.bold) { wanted.insert(.bold) }
        if traits.contains(.italic) { wanted.insert(.italic) }

        let base = PaperTheme.serif(size, weight: wanted.contains(.bold) ? .semibold : .regular)
        guard !wanted.isEmpty else { return base }
        let descriptor = base.fontDescriptor.withSymbolicTraits(wanted)
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// Paper is cream, not white. Text written light — for a dark theme, or as
    /// a watermark — would be unreadable here, so it is pulled back to ink.
    private static func readableInk(_ color: NSColor?) -> NSColor {
        guard let color, let srgb = color.usingColorSpace(.sRGB) else { return PaperTheme.ink }
        if srgb.alphaComponent < 0.35 { return PaperTheme.ink }

        let luminance = 0.2126 * srgb.redComponent
            + 0.7152 * srgb.greenComponent
            + 0.0722 * srgb.blueComponent
        return luminance > 0.68 ? PaperTheme.ink : srgb
    }

    /// Inline images arrive at their authored size, which can be far wider than
    /// the reading measure. The cell is replaced by a plain image so the size
    /// can be capped.
    private static func bound(_ attachment: NSTextAttachment) {
        let image = attachment.image ?? (attachment.attachmentCell as? NSTextAttachmentCell)?.image
        guard let image, image.size.width > 0, image.size.height > 0 else { return }

        let maximumWidth = PaperTheme.readingWidth - 80
        let scale = min(1, maximumWidth / image.size.width)
        attachment.attachmentCell = nil
        attachment.image = image
        attachment.bounds = NSRect(
            x: 0,
            y: 0,
            width: (image.size.width * scale).rounded(),
            height: (image.size.height * scale).rounded()
        )
    }
}
