import AppKit
import Foundation
import QuickLookThumbnailing

/// Asks macOS to draw the first page of a file FoldPeek has no reader for.
///
/// This is the fallback behind Keynote, Numbers, Pages, PowerPoint, Excel,
/// EPUB, and everything else in that shape. FoldPeek hands over a URL and
/// receives a bitmap: the decoding happens inside Apple's own thumbnail
/// service, out of process, and this extension never reads those bytes itself.
///
/// Only `.thumbnail` is requested. The icon representations are deliberately
/// excluded — a generic document icon is not a preview, and showing one would
/// claim content that was never read.
enum SystemPageRenderer {
    static let maximumFileBytes: Int64 = 512 * 1024 * 1024
    /// The page is rendered once at this size and then scaled to fit the card.
    private static let pageSize = CGSize(width: 1_000, height: 1_400)
    /// A stuck thumbnail service must not leave the pane reading "loading".
    private static let timeoutNanoseconds: UInt64 = 8 * 1_000_000_000

    static func render(url: URL, byteSize: Int64?) async -> NSImage? {
        if let byteSize, byteSize > maximumFileBytes { return nil }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: pageSize,
            scale: 2,
            representationTypes: .thumbnail
        )
        request.iconMode = false

        // The service is asked to stop rather than merely being abandoned, so
        // a slow render does not keep burning CPU after the pane gave up on it.
        let watchdog = Task {
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            guard !Task.isCancelled else { return }
            QLThumbnailGenerator.shared.cancel(request)
        }
        defer { watchdog.cancel() }

        let page: CGImage? = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
                if let error {
                    PreviewLog.failure("systemRender", error)
                }
                continuation.resume(returning: representation?.cgImage)
            }
        }

        guard let page else { return nil }
        return NSImage(cgImage: page, size: NSSize(width: page.width, height: page.height))
    }
}
