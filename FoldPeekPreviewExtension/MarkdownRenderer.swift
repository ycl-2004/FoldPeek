import AppKit

/// Renders a Markdown subset as styled text on the paper surface.
///
/// This is a scanner, not a document parser. It walks lines, recognises block
/// shapes, and applies the project's own typography. It never produces HTML,
/// never loads an image or a remote resource, and never attaches a `.link`
/// attribute — a URL in the source is shown as coloured text and nothing more.
///
/// Colour follows the brand's roles rather than decoration: denim carries
/// structure and anything technical, wine carries identity and judgement, and
/// body text stays ink.
enum MarkdownRenderer {
    /// Beyond this the file is shown as plain source instead. Layout of a
    /// heavily attributed string is the cost being bounded.
    static let maximumRenderCharacters = 200_000

    static let fileExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mdx"]

    static func canRender(pathExtension: String) -> Bool {
        fileExtensions.contains(pathExtension.lowercased())
    }

    static func render(_ text: String) -> NSAttributedString? {
        guard !text.isEmpty, text.utf16.count <= maximumRenderCharacters else { return nil }

        let output = NSMutableAttributedString()
        let lines = text.components(separatedBy: .newlines)
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let fence = fenceMarker(trimmed) {
                index = appendCodeBlock(lines, from: index, fence: fence, into: output)
                continue
            }
            if isHorizontalRule(trimmed) {
                output.append(rule(color: PaperTheme.hairline))
                index += 1
                continue
            }
            if let heading = headingLevel(trimmed) {
                output.append(headingParagraph(text: heading.text, level: heading.level))
                index += 1
                continue
            }
            if trimmed.hasPrefix(">") {
                index = appendQuote(lines, from: index, into: output)
                continue
            }
            if isTableRow(trimmed), index + 1 < lines.count,
               isTableSeparator(lines[index + 1].trimmingCharacters(in: .whitespaces)) {
                index = appendTable(lines, from: index, into: output)
                continue
            }
            if listMarker(line) != nil {
                index = appendList(lines, from: index, into: output)
                continue
            }
            if trimmed.isEmpty {
                index += 1
                continue
            }
            index = appendParagraph(lines, from: index, into: output)
        }

        return output
    }

    // MARK: - Type

    /// The four faces inline markup switches between. Tables use a monospaced
    /// set so emphasis cannot break column alignment.
    private struct FontSet {
        let regular: NSFont
        let bold: NSFont
        let italic: NSFont
        let code: NSFont

        func emphasised(bold isBold: Bool) -> FontSet {
            FontSet(
                regular: isBold ? bold : italic,
                bold: bold,
                italic: italic,
                code: code
            )
        }
    }

    private static func proseFonts(_ size: CGFloat, weight: NSFont.Weight = .regular) -> FontSet {
        FontSet(
            regular: PaperTheme.serif(size, weight: weight),
            bold: PaperTheme.serif(size, weight: .semibold),
            italic: PaperTheme.serifItalic(size, weight: weight),
            code: PaperTheme.mono(size - 1.5)
        )
    }

    private static func monoFonts(_ size: CGFloat, weight: NSFont.Weight = .regular) -> FontSet {
        FontSet(
            regular: PaperTheme.mono(size, weight: weight),
            bold: PaperTheme.mono(size, weight: .semibold),
            italic: PaperTheme.mono(size, weight: weight),
            code: PaperTheme.mono(size, weight: weight)
        )
    }

    // MARK: - Blocks

    private static func headingLevel(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        var rest = Substring(line)
        while rest.first == "#", level < 6 {
            level += 1
            rest = rest.dropFirst()
        }
        guard level > 0, rest.first == " " || rest.isEmpty else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func headingParagraph(text: String, level: Int) -> NSAttributedString {
        let sizes: [CGFloat] = [22, 17, 14.5, 13, 12.5, 12]
        let size = sizes[min(level, sizes.count) - 1]
        let color = level <= 3 ? PaperTheme.ink : PaperTheme.inkSoft

        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = level == 1 ? 6 : 22
        style.paragraphSpacing = 5
        style.lineSpacing = 3

        let result = NSMutableAttributedString(
            attributedString: inline(text, fonts: proseFonts(size, weight: .semibold), color: color)
        )
        result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: result.length))
        result.append(newline())

        // The top level carries a wine rule — the document's identity mark.
        // The second carries a neutral hairline, which is structure.
        if level == 1 {
            result.append(rule(color: PaperTheme.wine.withAlphaComponent(0.55), spacingBefore: 1, spacingAfter: 16))
        } else if level == 2 {
            result.append(rule(color: PaperTheme.hairline, spacingBefore: 1, spacingAfter: 12))
        }
        return result
    }

    private static func appendParagraph(
        _ lines: [String],
        from start: Int,
        into output: NSMutableAttributedString
    ) -> Int {
        var index = start
        var collected: [String] = []
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || headingLevel(trimmed) != nil || fenceMarker(trimmed) != nil
                || trimmed.hasPrefix(">") || listMarker(lines[index]) != nil
                || isHorizontalRule(trimmed) || isTableRow(trimmed) {
                break
            }
            collected.append(trimmed)
            index += 1
        }
        guard !collected.isEmpty else { return start + 1 }

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 8
        style.paragraphSpacing = 13

        let body = NSMutableAttributedString(
            attributedString: inline(
                collected.joined(separator: " "),
                fonts: proseFonts(12.5),
                color: PaperTheme.ink
            )
        )
        body.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: body.length))
        output.append(body)
        output.append(newline())
        return index
    }

    private static func appendQuote(
        _ lines: [String],
        from start: Int,
        into output: NSMutableAttributedString
    ) -> Int {
        var index = start
        var collected: [String] = []
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            collected.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
            index += 1
        }

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 7
        style.paragraphSpacingBefore = 6
        style.paragraphSpacing = 15
        style.firstLineHeadIndent = 18
        style.headIndent = 18

        let quote = NSMutableAttributedString(
            attributedString: inline(
                collected.joined(separator: " "),
                fonts: proseFonts(12.5),
                color: PaperTheme.inkSoft
            )
        )
        quote.addAttributes(
            // The wine rule beside it is drawn by the text view; a character
            // stand-in would wrap with the text and break alignment.
            [.paragraphStyle: style, .markdownQuote: true],
            range: NSRange(location: 0, length: quote.length)
        )
        output.append(quote)
        output.append(newline())
        return index
    }

    private static func appendList(
        _ lines: [String],
        from start: Int,
        into output: NSMutableAttributedString
    ) -> Int {
        var index = start
        while index < lines.count, let marker = listMarker(lines[index]) {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 7
            style.paragraphSpacing = 5
            let indent = CGFloat(marker.depth) * 18
            style.firstLineHeadIndent = indent
            style.headIndent = indent + 17

            let item = NSMutableAttributedString()
            // Denim marks structure, which is what a list marker is.
            item.append(NSAttributedString(
                string: marker.isOrdered ? "\(marker.label) " : "•  ",
                attributes: [
                    .font: marker.isOrdered ? PaperTheme.mono(10.5) : PaperTheme.serif(12.5),
                    .foregroundColor: PaperTheme.denim
                ]
            ))
            item.append(inline(marker.content, fonts: proseFonts(12.5), color: PaperTheme.ink))
            item.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: item.length))
            output.append(item)
            output.append(newline())
            index += 1
        }
        output.append(spacer(9))
        return index
    }

    private static func appendCodeBlock(
        _ lines: [String],
        from start: Int,
        fence: String,
        into output: NSMutableAttributedString
    ) -> Int {
        let language = lines[start]
            .trimmingCharacters(in: .whitespaces)
            .dropFirst(fence.count)
            .trimmingCharacters(in: .whitespaces)

        var index = start + 1
        var body: [String] = []
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(fence) { index += 1; break }
            body.append(lines[index])
            index += 1
        }

        let font = PaperTheme.mono(10.5)
        let source = body.joined(separator: "\n")
        let colored = CodeHighlighter.highlight(
            text: source,
            pathExtension: extensionForFence(language),
            font: font
        ) ?? NSAttributedString(
            string: source,
            attributes: [.font: font, .foregroundColor: PaperTheme.Syntax.plain]
        )

        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 14
        style.headIndent = 14
        style.paragraphSpacingBefore = 16
        style.paragraphSpacing = 20
        style.lineSpacing = 3

        let block = NSMutableAttributedString(attributedString: colored)
        block.addAttributes(
            // The panel behind it is drawn by the text view. A background
            // colour attribute paints per glyph run and leaves a ragged edge.
            [.paragraphStyle: style, .markdownCodeBlock: true],
            range: NSRange(location: 0, length: block.length)
        )
        output.append(block)
        output.append(newline())
        return index
    }

    /// Tables are laid out with padded monospace columns, which is the only
    /// alignment that survives CJK text without a real table engine. Cell
    /// markup is rendered in monospaced faces so emphasis cannot shift a column.
    private static func appendTable(
        _ lines: [String],
        from start: Int,
        into output: NSMutableAttributedString
    ) -> Int {
        var index = start
        var rows: [[String]] = []
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard isTableRow(trimmed) else { break }
            index += 1
            if isTableSeparator(trimmed) { continue }
            rows.append(splitRow(trimmed))
        }
        guard !rows.isEmpty else { return start + 1 }

        let columnCount = rows.map(\.count).max() ?? 0
        guard columnCount > 0 else { return index }

        // Render every cell first, so padding is measured on the visible text
        // rather than on the source with its markers still in it.
        var rendered: [[NSAttributedString]] = []
        var widths = [Int](repeating: 0, count: columnCount)
        for (rowIndex, row) in rows.enumerated() {
            var cells: [NSAttributedString] = []
            for column in 0..<columnCount {
                let source = column < row.count ? row[column] : ""
                let cell = inline(
                    source,
                    fonts: monoFonts(10, weight: rowIndex == 0 ? .semibold : .regular),
                    color: rowIndex == 0 ? PaperTheme.ink : PaperTheme.inkSoft
                )
                widths[column] = max(widths[column], displayWidth(cell.string))
                cells.append(cell)
            }
            rendered.append(cells)
        }

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
        style.paragraphSpacing = 7
        style.lineBreakMode = .byClipping
        style.firstLineHeadIndent = 16
        style.headIndent = 16

        let table = NSMutableAttributedString()
        for (rowIndex, cells) in rendered.enumerated() {
            let rowStart = table.length
            for (column, cell) in cells.enumerated() {
                table.append(cell)
                let padding = widths[column] - displayWidth(cell.string) + 3
                if padding > 0, column < columnCount - 1 {
                    table.append(NSAttributedString(
                        string: String(repeating: " ", count: padding),
                        attributes: [.font: PaperTheme.mono(10)]
                    ))
                }
            }
            // The row's index reaches the text view, which bands the header and
            // rules every row. A drawn rule tracks the real column widths; the
            // fixed-length dash line this replaces did not, which is why uneven
            // tables looked ragged.
            table.addAttribute(
                .markdownTableRow,
                value: NSNumber(value: rowIndex),
                range: NSRange(location: rowStart, length: table.length - rowStart)
            )
            table.append(newline())
        }
        table.addAttributes(
            [.paragraphStyle: style, .markdownTable: true],
            range: NSRange(location: 0, length: table.length)
        )
        output.append(table)
        output.append(spacer(16))
        return index
    }

    // MARK: - Inline

    /// Emphasis, code spans, strikethrough, and link text. Link URLs are shown
    /// but never made clickable.
    private static func inline(_ text: String, fonts: FontSet, color: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let characters = Array(text)
        var index = 0
        var plain = ""

        func flush() {
            guard !plain.isEmpty else { return }
            result.append(NSAttributedString(
                string: plain,
                attributes: [.font: fonts.regular, .foregroundColor: color]
            ))
            plain = ""
        }

        while index < characters.count {
            let character = characters[index]

            if character == "`", let end = findClosing(characters, from: index + 1, marker: "`", length: 1) {
                flush()
                let code = String(characters[(index + 1)..<end])
                // Denim is the brand's technical role; wine stays for identity.
                result.append(NSAttributedString(string: code, attributes: [
                    .font: fonts.code,
                    .foregroundColor: PaperTheme.denimDeep,
                    .backgroundColor: PaperTheme.denimTint
                ]))
                index = end + 1
                continue
            }

            if character == "*" || character == "_" {
                let isDouble = index + 1 < characters.count && characters[index + 1] == character
                let marker = String(character)
                let markerLength = isDouble ? 2 : 1
                if let end = findClosing(characters, from: index + markerLength, marker: marker, length: markerLength) {
                    flush()
                    let inner = String(characters[(index + markerLength)..<end])
                    result.append(inline(inner, fonts: fonts.emphasised(bold: isDouble), color: color))
                    index = end + markerLength
                    continue
                }
            }

            if character == "~", index + 1 < characters.count, characters[index + 1] == "~",
               let end = findClosing(characters, from: index + 2, marker: "~", length: 2) {
                flush()
                let inner = String(characters[(index + 2)..<end])
                result.append(NSAttributedString(string: inner, attributes: [
                    .font: fonts.regular,
                    .foregroundColor: PaperTheme.inkFaint,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue
                ]))
                index = end + 2
                continue
            }

            // [label](target) and the ![alt](target) image form.
            if character == "[" || (character == "!" && index + 1 < characters.count && characters[index + 1] == "[") {
                let isImage = character == "!"
                let bracketStart = isImage ? index + 1 : index
                if let labelEnd = findCharacter("]", in: characters, from: bracketStart + 1),
                   labelEnd + 1 < characters.count, characters[labelEnd + 1] == "(",
                   let targetEnd = findCharacter(")", in: characters, from: labelEnd + 2) {
                    flush()
                    let label = String(characters[(bracketStart + 1)..<labelEnd])
                    result.append(NSAttributedString(
                        string: isImage ? "🖼 \(label)" : label,
                        attributes: [
                            .font: fonts.regular,
                            .foregroundColor: PaperTheme.denim,
                            .underlineStyle: isImage ? 0 : NSUnderlineStyle.single.rawValue,
                            .underlineColor: PaperTheme.denim.withAlphaComponent(0.4)
                        ]
                    ))
                    index = targetEnd + 1
                    continue
                }
            }

            plain.append(character)
            index += 1
        }

        flush()
        return result
    }

    private static func findClosing(_ characters: [Character], from start: Int, marker: String, length: Int) -> Int? {
        let markerCharacter = marker.first!
        var index = start
        while index + length <= characters.count {
            if characters[index] == markerCharacter {
                if length == 1 { return index }
                if index + 1 < characters.count, characters[index + 1] == markerCharacter { return index }
            }
            if characters[index] == "\n" { return nil }
            index += 1
        }
        return nil
    }

    private static func findCharacter(_ target: Character, in characters: [Character], from start: Int) -> Int? {
        var index = start
        while index < characters.count {
            if characters[index] == target { return index }
            index += 1
        }
        return nil
    }

    // MARK: - Line shapes

    private static func fenceMarker(_ line: String) -> String? {
        if line.hasPrefix("```") { return "```" }
        if line.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        let stripped = line.replacingOccurrences(of: " ", with: "")
        return stripped.allSatisfy { $0 == "-" } || stripped.allSatisfy { $0 == "*" }
            || stripped.allSatisfy { $0 == "_" }
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.hasPrefix("|") && line.contains("|") && line.count > 1
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        guard isTableRow(line) else { return false }
        let stripped = line.replacingOccurrences(of: " ", with: "")
        return stripped.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" } && stripped.contains("-")
    }

    private static func splitRow(_ line: String) -> [String] {
        line.split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst()
            .dropLast()
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private struct ListMarker {
        let depth: Int
        let isOrdered: Bool
        let label: String
        let content: String
    }

    private static func listMarker(_ line: String) -> ListMarker? {
        var leading = 0
        for character in line {
            if character == " " { leading += 1 } else if character == "\t" { leading += 4 } else { break }
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let depth = leading / 2

        if let first = trimmed.first, first == "-" || first == "*" || first == "+" {
            let rest = trimmed.dropFirst()
            guard rest.first == " " else { return nil }
            return ListMarker(
                depth: depth, isOrdered: false, label: "",
                content: rest.trimmingCharacters(in: .whitespaces)
            )
        }

        var digits = ""
        var rest = Substring(trimmed)
        while let first = rest.first, first.isNumber, digits.count < 4 {
            digits.append(first)
            rest = rest.dropFirst()
        }
        guard !digits.isEmpty, rest.first == "." || rest.first == ")" else { return nil }
        rest = rest.dropFirst()
        guard rest.first == " " else { return nil }
        return ListMarker(
            depth: depth, isOrdered: true, label: "\(digits).",
            content: rest.trimmingCharacters(in: .whitespaces)
        )
    }

    // MARK: - Pieces

    private static func newline() -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: [.font: PaperTheme.serif(12.5)])
    }

    private static func spacer(_ points: CGFloat) -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: points)])
    }

    private static func rule(
        color: NSColor,
        spacingBefore: CGFloat = 10,
        spacingAfter: CGFloat = 16
    ) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        // Clipping keeps the rule on one line instead of wrapping into a block.
        style.lineBreakMode = .byClipping

        let line = NSMutableAttributedString(
            string: String(repeating: "─", count: 240),
            attributes: [
                .font: PaperTheme.mono(9),
                .foregroundColor: color,
                .paragraphStyle: style
            ]
        )
        line.append(newline())
        return line
    }

    /// CJK and fullwidth characters occupy two cells in a monospaced run.
    private static func displayWidth(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { total, scalar in
            switch scalar.value {
            case 0x1100...0x115F, 0x2E80...0xA4CF, 0xAC00...0xD7A3,
                 0xF900...0xFAFF, 0xFE30...0xFE6F, 0xFF00...0xFF60, 0xFFE0...0xFFE6:
                return total + 2
            default:
                return total + 1
            }
        }
    }

    private static func extensionForFence(_ language: String) -> String {
        switch language.lowercased() {
        case "swift": return "swift"
        case "python", "py": return "py"
        case "javascript", "js", "typescript", "ts", "jsx", "tsx": return "js"
        case "json": return "json"
        case "bash", "sh", "shell", "zsh": return "sh"
        case "yaml", "yml": return "yml"
        case "css", "scss": return "css"
        case "html", "xml": return "html"
        case "c", "cpp", "objc", "java", "go", "rust", "rs", "kotlin": return "c"
        default: return language.lowercased()
        }
    }
}
