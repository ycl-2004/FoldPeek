import AppKit

/// Sets one worksheet as a ruled table on the paper surface.
///
/// The layout is the same one `MarkdownRenderer` uses for its tables: padded
/// monospace columns, and the `.markdownTable` / `.markdownTableRow` attributes
/// that `CodeTextView` reads to band the header and rule each row. Reusing
/// those attributes is deliberate — a spreadsheet and a Markdown table are the
/// same thing on the page, and they should not be drawn by two sets of rules.
///
/// Cell text arrives as characters and is set as characters. Nothing here reads
/// a cell as markup, a formula, or a reference.
enum WorkbookRenderer {
    /// A row wider than this is cut, because past it the columns no longer
    /// align on any pane a person would actually open.
    static let maximumRenderedColumns = 16
    /// Characters shown per cell before the column is elided.
    static let maximumRenderedCellWidth = 28

    static func render(_ sheet: Workbook.Sheet) -> NSAttributedString {
        guard !sheet.rows.isEmpty else {
            return NSAttributedString(
                string: "此工作表为空。",
                attributes: [
                    .font: PaperTheme.serif(12),
                    .foregroundColor: PaperTheme.inkSoft
                ]
            )
        }

        let columnCount = min(sheet.rows.map(\.count).max() ?? 0, maximumRenderedColumns)
        guard columnCount > 0 else {
            return NSAttributedString(string: "此工作表为空。", attributes: [
                .font: PaperTheme.serif(12),
                .foregroundColor: PaperTheme.inkSoft
            ])
        }

        // Widths are measured on the elided text, so a single long cell cannot
        // push every other column off the pane.
        var cells: [[String]] = []
        var widths = [Int](repeating: 0, count: columnCount)
        for row in sheet.rows {
            var rendered: [String] = []
            for column in 0..<columnCount {
                let text = elide(column < row.count ? row[column] : "")
                widths[column] = max(widths[column], displayWidth(text))
                rendered.append(text)
            }
            cells.append(rendered)
        }

        let output = NSMutableAttributedString()
        let gutterWidth = displayWidth("\(sheet.rows.count)")

        for (rowIndex, row) in cells.enumerated() {
            let rowStart = output.length

            // A row number, so a reader can say which line they are looking at
            // the way they would in the spreadsheet itself.
            let label = "\(rowIndex + 1)"
            output.append(NSAttributedString(
                string: String(repeating: " ", count: gutterWidth - displayWidth(label)) + label + "  ",
                attributes: [
                    .font: PaperTheme.mono(9),
                    .foregroundColor: PaperTheme.Syntax.gutterText
                ]
            ))

            for (column, text) in row.enumerated() {
                output.append(NSAttributedString(
                    string: text,
                    attributes: [
                        .font: PaperTheme.mono(10, weight: rowIndex == 0 ? .semibold : .regular),
                        .foregroundColor: rowIndex == 0 ? PaperTheme.ink : PaperTheme.inkSoft
                    ]
                ))
                let padding = widths[column] - displayWidth(text) + 3
                if padding > 0, column < columnCount - 1 {
                    output.append(NSAttributedString(
                        string: String(repeating: " ", count: padding),
                        attributes: [.font: PaperTheme.mono(10)]
                    ))
                }
            }

            output.addAttribute(
                .markdownTableRow,
                value: NSNumber(value: rowIndex),
                range: NSRange(location: rowStart, length: output.length - rowStart)
            )
            output.append(NSAttributedString(
                string: "\n",
                attributes: [.font: PaperTheme.mono(10)]
            ))
        }

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
        style.paragraphSpacing = 7
        style.lineBreakMode = .byClipping
        style.firstLineHeadIndent = 16
        style.headIndent = 16

        output.addAttributes(
            [.paragraphStyle: style, .markdownTable: true],
            range: NSRange(location: 0, length: output.length)
        )

        if sheet.isTruncated {
            output.append(note("此工作表超出上限，仅显示前 \(WorkbookReader.maximumRows) 行。"))
        }
        if (sheet.rows.map(\.count).max() ?? 0) > maximumRenderedColumns {
            output.append(note("列数超出上限，仅显示前 \(maximumRenderedColumns) 列。"))
        }
        return output
    }

    private static func note(_ text: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 12
        style.firstLineHeadIndent = 16
        style.headIndent = 16
        return NSAttributedString(
            string: "\n" + text,
            attributes: [
                .font: PaperTheme.mono(9),
                .foregroundColor: PaperTheme.inkFaint,
                .paragraphStyle: style
            ]
        )
    }

    private static func elide(_ text: String) -> String {
        guard displayWidth(text) > maximumRenderedCellWidth else { return text }
        var kept = ""
        var width = 0
        for character in text {
            let step = displayWidth(String(character))
            if width + step > maximumRenderedCellWidth - 1 { break }
            kept.append(character)
            width += step
        }
        return kept + "…"
    }

    /// Full-width characters occupy two monospace cells; without this the
    /// columns of any CJK sheet drift apart.
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
}
