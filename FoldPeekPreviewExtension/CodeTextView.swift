import AppKit

extension NSAttributedString.Key {
    /// Marks a fenced code block, so the view can paint one solid panel behind
    /// it. A background colour attribute paints per glyph run and leaves a
    /// ragged edge wherever a line is short.
    static let markdownCodeBlock = NSAttributedString.Key("foldpeek.markdown.codeBlock")
    /// Marks a block quote, so the view can draw its wine rule.
    static let markdownQuote = NSAttributedString.Key("foldpeek.markdown.quote")
    /// Marks a whole table, for its panel and border.
    static let markdownTable = NSAttributedString.Key("foldpeek.markdown.table")
    /// Marks one table row, carrying its index so the header can be banded and
    /// every row ruled off.
    static let markdownTableRow = NSAttributedString.Key("foldpeek.markdown.tableRow")
}

/// A read-only text view that reads like an editor: indentation guides behind
/// the text, and line numbers in a gutter.
///
/// Everything drawn here is computed from the plain characters already loaded.
/// The view never re-reads the file and never interprets it as a document.
final class CodeTextView: NSTextView {
    /// Guides suit source, not prose; Markdown turns them off.
    var drawsIndentGuides = true {
        didSet { needsDisplay = true }
    }

    /// Caps the measure for prose and centres it. Source is left unbounded,
    /// because wrapping a long line is worse than a long line.
    var maximumReadingWidth: CGFloat? {
        didSet { updateReadingInset() }
    }

    /// The inset used when no reading cap applies.
    var baseInset = NSSize(width: 10, height: 10) {
        didSet { updateReadingInset() }
    }

    /// Columns per indentation level, detected from the text itself.
    private(set) var indentUnit = 4
    private var columnWidth: CGFloat = 7

    /// Recomputes the metrics the guides depend on. Call after setting text.
    func refreshCodeMetrics() {
        columnWidth = (" " as NSString)
            .size(withAttributes: [.font: font ?? PaperTheme.mono(11)])
            .width
        indentUnit = Self.detectIndentUnit(in: string)
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateReadingInset()
    }

    private func updateReadingInset() {
        guard let maximumReadingWidth else {
            if textContainerInset != baseInset { textContainerInset = baseInset }
            return
        }
        let sideInset = max(baseInset.width, (frame.width - maximumReadingWidth) / 2)
        let target = NSSize(width: sideInset, height: baseInset.height)
        if textContainerInset != target { textContainerInset = target }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Decorations first, so the text lands on top of them.
        drawMarkdownBlocks(in: dirtyRect)
        drawIndentGuides(in: dirtyRect)
        super.draw(dirtyRect)
    }

    /// Paints the panels behind fenced code and tables, the rules inside a
    /// table, and the bar beside a quote.
    private func drawMarkdownBlocks(in dirtyRect: NSRect) {
        guard let layoutManager, let textContainer, let textStorage,
              textStorage.length > 0
        else { return }

        let origin = textContainerOrigin
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: dirtyRect, in: textContainer)
        let visibleRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard visibleRange.length > 0 else { return }

        func boundingRect(of range: NSRange) -> NSRect {
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            return layoutManager
                .boundingRect(forGlyphRange: glyphs, in: textContainer)
                .offsetBy(dx: origin.x, dy: origin.y)
        }

        /// Walks the marked spans intersecting the dirty rect, handing back the
        /// span's *whole* range each time.
        ///
        /// AppKit redraws in horizontal bands, so a span crossing two bands is
        /// visited twice with two clipped ranges. Drawing those directly gave
        /// one rounded panel per band — the fragments seen stacked on top of
        /// each other. Expanding to the longest effective range and skipping
        /// repeats keeps every span a single shape.
        func forEachSpan(_ key: NSAttributedString.Key, _ body: (Any, NSRange) -> Void) {
            var seen = Set<Int>()
            textStorage.enumerateAttribute(key, in: visibleRange) { value, range, _ in
                guard let value else { return }
                var effective = NSRange()
                _ = textStorage.attribute(
                    key, at: range.location, longestEffectiveRange: &effective, in: fullRange
                )
                guard seen.insert(effective.location).inserted else { return }
                body(value, effective)
            }
        }

        forEachSpan(.markdownCodeBlock) { _, range in
            var rect = boundingRect(of: range)
            // Span the measure, not just the longest line.
            rect.origin.x = origin.x
            rect.size.width = textContainer.size.width
            rect = rect.insetBy(dx: 0, dy: -8)

            let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
            PaperTheme.surfaceMuted.withAlphaComponent(0.55).setFill()
            path.fill()
            PaperTheme.borderSubtle.setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        forEachSpan(.markdownTable) { _, range in
            var rect = boundingRect(of: range)
            rect.origin.x = origin.x
            rect.size.width = textContainer.size.width
            rect = rect.insetBy(dx: 0, dy: -6)

            let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
            PaperTheme.paper.setFill()
            path.fill()
            PaperTheme.hairline.setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        // Ruling every row is what makes a table with uneven columns scannable.
        forEachSpan(.markdownTableRow) { value, range in
            guard let index = (value as? NSNumber)?.intValue else { return }
            var rect = boundingRect(of: range)
            rect.origin.x = origin.x
            rect.size.width = textContainer.size.width

            if index == 0 {
                let band = rect.insetBy(dx: 0, dy: -4)
                PaperTheme.denimTint.setFill()
                band.fill()
                PaperTheme.denim.withAlphaComponent(0.30).setFill()
                NSRect(x: band.minX, y: band.maxY - 1, width: band.width, height: 1).fill()
            } else {
                PaperTheme.borderSubtle.setFill()
                NSRect(x: rect.minX + 8, y: rect.maxY + 3, width: rect.width - 16, height: 1).fill()
            }
        }

        forEachSpan(.markdownQuote) { _, range in
            let rect = boundingRect(of: range)
            let bar = NSRect(x: origin.x + 2, y: rect.minY - 1, width: 3, height: rect.height + 2)
            PaperTheme.wine.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    private func drawIndentGuides(in dirtyRect: NSRect) {
        guard drawsIndentGuides,
              let layoutManager, let textContainer, columnWidth > 0, !string.isEmpty
        else { return }

        let source = string as NSString
        let origin = textContainerOrigin
        let glyphRange = layoutManager.glyphRange(forBoundingRect: dirtyRect, in: textContainer)

        let guides = NSBezierPath()
        guides.lineWidth = 1

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, fragmentGlyphs, _ in
            let charRange = layoutManager.characterRange(forGlyphRange: fragmentGlyphs, actualGlyphRange: nil)
            guard charRange.location < source.length else { return }

            // Wrapped fragments inherit the indent of their paragraph.
            let paragraph = source.paragraphRange(for: NSRange(location: charRange.location, length: 0))
            let levels = Self.indentLevels(of: source, in: paragraph, unit: self.indentUnit)
            guard levels > 1 else { return }

            for level in 1..<levels {
                let x = (origin.x + CGFloat(level * self.indentUnit) * self.columnWidth).rounded() + 0.5
                guides.move(to: NSPoint(x: x, y: usedRect.minY + origin.y))
                guides.line(to: NSPoint(x: x, y: usedRect.maxY + origin.y))
            }
        }

        PaperTheme.Syntax.guide.setStroke()
        guides.stroke()
    }

    // MARK: - Indentation

    /// How many guide columns a line sits behind.
    private static func indentLevels(of source: NSString, in paragraph: NSRange, unit: Int) -> Int {
        var spaces = 0
        var tabs = 0
        var index = paragraph.location
        let end = min(paragraph.location + paragraph.length, source.length)

        while index < end {
            switch source.character(at: index) {
            case 32: spaces += 1
            case 9: tabs += 1
            default:
                // A blank line carries no indent worth drawing.
                if source.character(at: index) == 10 || source.character(at: index) == 13 { return 0 }
                return tabs > 0 ? tabs : (unit > 0 ? spaces / unit : 0)
            }
            index += 1
        }
        return 0
    }

    /// The smallest positive indent step in the file, which is the unit the
    /// author actually used. Clamped so a one-space file does not draw a guide
    /// against every character.
    private static func detectIndentUnit(in text: String) -> Int {
        var smallest = Int.max
        var inspected = 0

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            inspected += 1
            if inspected > 500 { break }
            var spaces = 0
            for character in line {
                if character == " " { spaces += 1 } else { break }
            }
            if spaces > 0 { smallest = min(smallest, spaces) }
        }

        guard smallest != Int.max else { return 4 }
        return min(max(smallest, 2), 8)
    }
}

// MARK: - Gutter

/// Line numbers down the left edge of the code card.
final class LineNumberRulerView: NSRulerView {
    /// UTF-16 offsets where each line begins, so the first visible line can be
    /// found by binary search instead of counting newlines on every draw.
    private var lineStarts: [Int] = [0]

    init(textView: NSTextView, scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 38
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh(for text: NSString) {
        var starts = [0]
        var index = 0
        while index < text.length {
            if text.character(at: index) == 10 { starts.append(index + 1) }
            index += 1
        }
        lineStarts = starts

        let digits = max(2, String(starts.count).count)
        ruleThickness = CGFloat(digits) * 8 + 20
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer,
              let visibleRect = scrollView?.contentView.bounds
        else { return }

        PaperTheme.hairline.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()

        let source = textView.string as NSString
        guard source.length > 0 else { return }

        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let origin = textView.textContainerOrigin
        let relative = convert(NSPoint.zero, from: textView)

        var lineIndex = lineNumber(containing: charRange.location)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: PaperTheme.mono(9),
            .foregroundColor: PaperTheme.Syntax.gutterText
        ]

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, fragmentGlyphs, _ in
            let fragmentChars = layoutManager.characterRange(forGlyphRange: fragmentGlyphs, actualGlyphRange: nil)

            // Only the fragment that starts a line gets a number; wrapped
            // continuations stay blank, the way an editor prints them.
            guard lineIndex < self.lineStarts.count,
                  fragmentChars.location == self.lineStarts[lineIndex]
            else { return }

            let label = "\(lineIndex + 1)" as NSString
            let size = label.size(withAttributes: attributes)
            let y = relative.y + origin.y + usedRect.minY + (usedRect.height - size.height) / 2
            label.draw(
                at: NSPoint(x: self.bounds.maxX - size.width - 9, y: y),
                withAttributes: attributes
            )
            lineIndex += 1
        }
    }

    private func lineNumber(containing offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lineStarts[middle] <= offset { low = middle } else { high = middle - 1 }
        }
        return low
    }
}
