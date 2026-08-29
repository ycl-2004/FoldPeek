import AppKit

/// The paper-inspector design tokens.
///
/// The palette is deliberately fixed rather than semantic: this is a warm
/// paper surface, and letting it invert in Dark Mode would turn the cream
/// index and the wine accents into something the design never describes.
enum PaperTheme {
    // MARK: - Palette

    /// Index pane, the warmer of the two surfaces.
    static let cream = srgb(0xFA, 0xF6, 0xEB)
    /// Content pane, the near-white sheet the inspector is printed on.
    static let paper = srgb(0xFF, 0xFD, 0xF8)
    /// Primary text.
    static let ink = srgb(0x1A, 0x1A, 0x2E)
    /// Secondary text: metadata, counts, captions.
    static let inkSoft = srgb(0x62, 0x62, 0x72)
    /// Identity, section numerals, and file type marks.
    static let wine = srgb(0xB2, 0x3A, 0x48)
    /// System iconography.
    static let denim = srgb(0x3B, 0x6E, 0xA5)
    /// Selected row fill.
    static let denimSoft = srgb(0xDC, 0xE7, 0xF2)

    /// Emotion accent. Used sparingly, never for body text.
    static let blush = srgb(0xCB, 0x5A, 0x78)
    /// Readable system text on a light surface.
    static let denimDeep = srgb(0x34, 0x62, 0x94)
    /// The lightest denim surface, for technical insets.
    static let denimTint = srgb(0xEE, 0xF4, 0xFA)
    /// A warm neutral surface, one step down from paper.
    static let surfaceMuted = srgb(0xF1, 0xED, 0xE2)

    // Semantic states. Wine is brand and primary action only — never an error.
    static let success = srgb(0x5E, 0x8C, 0x68)
    static let warning = srgb(0xBE, 0x7A, 0x2E)
    static let error = srgb(0xCB, 0x4B, 0x33)

    static let hairline = ink.withAlphaComponent(0.12)
    static let borderSubtle = ink.withAlphaComponent(0.08)
    /// The paper grain, at the brand's --tex-line strength.
    static let hairlineFaint = ink.withAlphaComponent(0.05)
    static let inkFaint = ink.withAlphaComponent(0.35)

    // MARK: - Type

    /// Serif carries names and titles — the "printed" half of the design.
    static func serif(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// Italic serif, used only for the section numeral.
    static func serifItalic(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = serif(size, weight: weight)
        let descriptor = base.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// Monospace carries every figure: dates, sizes, paths, depth.
    static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    // MARK: - Code

    /// Syntax colours, chosen to sit on paper rather than on a dark editor:
    /// muted, low-chroma, and sharing the wine and denim of the rest of the UI.
    enum Syntax {
        static let plain = PaperTheme.ink
        static let keyword = PaperTheme.wine
        static let string = srgb(0x4F, 0x7A, 0x5A)
        static let number = srgb(0x7A, 0x5E, 0xA8)
        static let comment = srgb(0x92, 0x92, 0xA0)
        /// Object keys, so JSON reads as a structure rather than a wall of strings.
        static let key = srgb(0x2F, 0x6F, 0x8F)

        /// Bracket pairs cycle through these by nesting depth, the way VS Code
        /// colours pairs, so a run of closing braces is readable at a glance.
        static let bracketDepths: [NSColor] = [
            PaperTheme.denim,
            PaperTheme.wine,
            srgb(0xC0, 0x8A, 0x2E),
            srgb(0x4F, 0x7A, 0x5A),
            srgb(0x7A, 0x5E, 0xA8)
        ]

        /// Indentation guides and the gutter rule.
        static let guide = PaperTheme.ink.withAlphaComponent(0.09)
        static let gutterText = PaperTheme.ink.withAlphaComponent(0.28)
    }

    // MARK: - Categories

    /// One hue per file group.
    ///
    /// These are printing-ink colours, not screen colours: every one is held
    /// between roughly 30% and 55% luminance so it stays legible on cream at
    /// 8 pt, and chroma is kept low so a dozen of them stacked down one column
    /// reads as an organised index rather than a paint chart. Folder denim,
    /// document wine, and code steel are the existing brand roles reused, so
    /// the palette does not introduce a second visual language.
    enum Category {
        static func color(for category: FileCategory) -> NSColor {
            switch category {
            case .folder: return PaperTheme.denim
            case .symbolicLink: return srgb(0x8A, 0x86, 0x94)
            case .document: return PaperTheme.wine
            case .spreadsheet: return srgb(0x3F, 0x7D, 0x55)
            case .presentation: return srgb(0xC0, 0x7A, 0x24)
            case .image: return srgb(0x7A, 0x5E, 0xA8)
            case .video: return srgb(0xA8, 0x46, 0x6F)
            case .audio: return srgb(0x2A, 0x83, 0x86)
            case .code: return srgb(0x37, 0x60, 0x7F)
            case .text: return srgb(0x6B, 0x62, 0x50)
            case .data: return srgb(0x86, 0x70, 0x2A)
            case .archive: return srgb(0x7A, 0x6A, 0x5E)
            case .other: return PaperTheme.inkSoft
            }
        }

        /// The wash behind a type chip. Light enough that the ink on top of it
        /// keeps its contrast, strong enough to read as a swatch.
        static let chipFill: CGFloat = 0.11
        static let chipStroke: CGFloat = 0.22
    }

    // MARK: - Metrics

    /// Spacing of the preview card's paper grain.
    static let paperGrainSpacing: CGFloat = 22
    static let cardCornerRadius: CGFloat = 12
    static let rowCornerRadius: CGFloat = 8
    /// Long-form measure. Prose is centred within this rather than filling a
    /// wide panel edge to edge.
    static let readingWidth: CGFloat = 720

    private static func srgb(_ red: Int, _ green: Int, _ blue: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }
}
