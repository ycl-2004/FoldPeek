import AppKit
import PDFKit

/// The PDF surface: pages are drawn, and nothing on them is a doorway out.
///
/// PDFKit gives the scrolling, the page breaks, and the text selection that a
/// bitmap of page one cannot. What it also gives by default is a live link
/// annotation, which opens a URL in the user's browser on a single click.
/// Implementing `pdfView(_:clickedLink:)` is what takes that behaviour away —
/// PDFKit only opens the URL itself when no delegate claims the message — so
/// the empty body below is the whole point of this subclass.
final class PaperPDFView: PDFView {
    /// PDFKit opens a clicked link's URL unless its delegate claims the
    /// message. The delegate is deliberately a separate object, never the view
    /// itself: PDFView reading its own weak delegate while re-scaling crashes
    /// on current macOS.
    private let linkSwallower = LinkSwallower()

    init() {
        super.init(frame: .zero)
        // `autoScales` is deliberately absent here. Flipping it on an empty,
        // zero-sized view makes PDFKit run its scale-change machinery against a
        // nonexistent page, recursing until the delegate read crashes. It is
        // armed only when a document is shown, on a view with a real frame.
        displayMode = .singlePageContinuous
        displayDirection = .vertical
        displaysPageBreaks = true
        pageShadowsEnabled = false
        // Data detectors turn phone numbers and addresses into actions.
        enableDataDetectors = false
        interpolationQuality = .high
        backgroundColor = PaperTheme.paper
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        displayMode = .singlePageContinuous
        displayDirection = .vertical
        displaysPageBreaks = true
        pageShadowsEnabled = false
        enableDataDetectors = false
        interpolationQuality = .high
        backgroundColor = PaperTheme.paper
    }

    /// Arms the surface for a real document. By the time a PDF is selected the
    /// view has a frame and a laid-out window, so `autoScales` follows the
    /// ordinary, well-trodden path instead of running during layout.
    func showDocument(_ document: PDFDocument) {
        delegate = linkSwallower
        self.document = document
        autoScales = true
    }

    /// Releases the mapped document and its page cache when the pane moves on.
    func unload() {
        document = nil
    }
}

/// Swallows every link click. Destinations stay visible in the page; none of
/// them launches anything.
private final class LinkSwallower: NSObject, PDFViewDelegate {
    func pdfView(_ sender: PDFView, clickedLink url: URL) {}
}

/// Holds a system-rendered page: fitted to the card, centred, and never
/// enlarged past its own pixels — an upscaled bitmap only looks broken.
final class RenderedPageView: NSView {
    var image: NSImage? {
        didSet {
            imageView.image = image
            needsLayout = true
        }
    }

    private let imageView = NSImageView()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        assemble()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        assemble()
    }

    private func assemble() {
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.borderWidth = 1
        imageView.layer?.borderColor = PaperTheme.hairline.cgColor
        addSubview(imageView)
    }

    /// Laid out by hand rather than by constraints so the hairline sits tight
    /// against the page instead of around the image view's slack.
    override func layout() {
        super.layout()
        guard let image, image.size.width > 0, image.size.height > 0 else {
            imageView.frame = .zero
            return
        }

        let scale = min(
            bounds.width / image.size.width,
            bounds.height / image.size.height,
            1
        )
        let size = NSSize(
            width: (image.size.width * scale).rounded(),
            height: (image.size.height * scale).rounded()
        )
        imageView.frame = NSRect(
            x: ((bounds.width - size.width) / 2).rounded(),
            y: ((bounds.height - size.height) / 2).rounded(),
            width: size.width,
            height: size.height
        )
    }
}
