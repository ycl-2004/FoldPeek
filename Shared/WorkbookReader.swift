import Foundation

/// One spreadsheet, read as text.
struct Workbook {
    struct Sheet {
        let name: String
        /// Rows of cells, already padded to a common width.
        let rows: [[String]]
        /// True when the sheet had more rows or columns than the caps allow.
        let isTruncated: Bool

        var isEmpty: Bool { rows.isEmpty }
    }

    let sheets: [Sheet]
}

/// Reads the sheets of an Office Open XML workbook.
///
/// This exists because a spreadsheet is the one document kind where the
/// system's single page image is nearly useless: a twenty-sheet workbook has
/// nineteen sheets that no picture of the first one will ever show.
///
/// Only four entries are ever read, all by exact name: the workbook, its
/// relationships, the shared string table, and one worksheet at a time. Cells
/// are turned into strings and nothing else — no formula is evaluated, no
/// reference is followed, and a cell's text is never treated as markup.
enum WorkbookReader {
    /// Rows kept per sheet. Beyond this the sheet is marked truncated.
    static let maximumRows = 400
    /// Columns kept per row.
    static let maximumColumns = 32
    /// Characters kept per cell.
    static let maximumCellLength = 240
    /// Entries in the shared string table.
    static let maximumSharedStrings = 200_000

    static func handles(pathExtension: String) -> Bool {
        ["xlsx", "xlsm"].contains(pathExtension.lowercased())
    }

    static func read(at url: URL) -> Workbook? {
        guard let archive = ZipArchive(url: url),
              let workbookData = archive.data(for: "xl/workbook.xml")
        else { return nil }

        let relationships = archive.data(for: "xl/_rels/workbook.xml.rels")
            .map(parseRelationships) ?? [:]
        let sharedStrings = archive.data(for: "xl/sharedStrings.xml")
            .map(parseSharedStrings) ?? []

        var sheets: [Workbook.Sheet] = []
        for descriptor in parseSheetList(workbookData) {
            guard let target = relationships[descriptor.relationshipID] else { continue }
            // Relationship targets are relative to the xl/ directory, and the
            // leading slash form is absolute within the package. Neither is
            // resolved as a filesystem path; it only selects an archive entry.
            let entry = target.hasPrefix("/")
                ? String(target.dropFirst())
                : "xl/" + target
            guard let sheetData = archive.data(for: entry) else { continue }

            let parsed = parseSheet(sheetData, sharedStrings: sharedStrings)
            sheets.append(
                Workbook.Sheet(
                    name: descriptor.name,
                    rows: parsed.rows,
                    isTruncated: parsed.isTruncated
                )
            )
        }

        guard !sheets.isEmpty else { return nil }
        return Workbook(sheets: sheets)
    }

    // MARK: - workbook.xml

    private struct SheetDescriptor {
        let name: String
        let relationshipID: String
    }

    private static func parseSheetList(_ data: Data) -> [SheetDescriptor] {
        var scanner = XMLScanner(data)
        var sheets: [SheetDescriptor] = []

        while let token = scanner.next() {
            guard case let .start(name, attributes, _) = token, name == "sheet" else { continue }
            let title = attributes["name"] ?? "Sheet \(sheets.count + 1)"
            guard let relationship = attributes["r:id"] ?? attributes["id"] else { continue }
            sheets.append(SheetDescriptor(name: title, relationshipID: relationship))
        }
        return sheets
    }

    private static func parseRelationships(_ data: Data) -> [String: String] {
        var scanner = XMLScanner(data)
        var map: [String: String] = [:]

        while let token = scanner.next() {
            guard case let .start(name, attributes, _) = token, name == "Relationship" else { continue }
            guard let id = attributes["Id"], let target = attributes["Target"] else { continue }
            map[id] = target
        }
        return map
    }

    // MARK: - sharedStrings.xml

    /// Each `<si>` is one string, but rich text splits it across several `<t>`
    /// runs, so the runs inside an item are joined.
    private static func parseSharedStrings(_ data: Data) -> [String] {
        var scanner = XMLScanner(data)
        var strings: [String] = []
        var current = ""
        var insideItem = false
        var insideText = false

        while let token = scanner.next(), strings.count < maximumSharedStrings {
            switch token {
            case let .start(name, _, isSelfClosing):
                if name == "si" {
                    insideItem = true
                    current = ""
                } else if name == "t", insideItem, !isSelfClosing {
                    insideText = true
                }
            case let .end(name):
                if name == "t" {
                    insideText = false
                } else if name == "si", insideItem {
                    strings.append(current)
                    insideItem = false
                }
            case let .text(value):
                if insideText { current += value }
            }
        }
        return strings
    }

    // MARK: - worksheet

    private static func parseSheet(
        _ data: Data,
        sharedStrings: [String]
    ) -> (rows: [[String]], isTruncated: Bool) {
        var scanner = XMLScanner(data)
        var rows: [[String]] = []
        var currentRow: [String] = []

        var cellColumn = 0
        var cellType = ""
        var cellValue = ""
        var insideValue = false
        var insideInlineText = false
        var widestRow = 0
        var isTruncated = false

        func finishCell() {
            guard cellColumn < maximumColumns else {
                isTruncated = true
                return
            }
            let text = resolve(value: cellValue, type: cellType, sharedStrings: sharedStrings)
            if currentRow.count <= cellColumn {
                currentRow.append(contentsOf: repeatElement("", count: cellColumn - currentRow.count + 1))
            }
            currentRow[cellColumn] = text
        }

        while let token = scanner.next() {
            switch token {
            case let .start(name, attributes, isSelfClosing):
                switch name {
                case "row":
                    currentRow = []
                case "c":
                    cellType = attributes["t"] ?? ""
                    cellValue = ""
                    cellColumn = column(fromReference: attributes["r"] ?? "", fallback: currentRow.count)
                    if isSelfClosing { finishCell() }
                case "v":
                    insideValue = !isSelfClosing
                case "t":
                    insideInlineText = !isSelfClosing
                default:
                    break
                }
            case let .end(name):
                switch name {
                case "v":
                    insideValue = false
                case "t":
                    insideInlineText = false
                case "c":
                    finishCell()
                case "row":
                    if rows.count < maximumRows {
                        widestRow = max(widestRow, currentRow.count)
                        rows.append(currentRow)
                    } else {
                        isTruncated = true
                    }
                default:
                    break
                }
            case let .text(value):
                if insideValue || insideInlineText { cellValue += value }
            }
        }

        // Trailing empty rows carry no information and only lengthen the table.
        while let last = rows.last, last.allSatisfy(\.isEmpty) {
            rows.removeLast()
        }

        // A sheet's used range is usually far narrower than its widest row's
        // cell references suggest, because empty styled cells are still
        // written out. Columns are trimmed to the last one holding text, so a
        // one-column sheet is not laid out fifteen columns wide.
        var lastUsedColumn = -1
        for row in rows {
            for (column, cell) in row.enumerated() where !cell.isEmpty {
                lastUsedColumn = max(lastUsedColumn, column)
            }
        }
        guard lastUsedColumn >= 0 else { return ([], isTruncated) }

        let width = min(lastUsedColumn + 1, widestRow)
        let padded = rows.map { row -> [String] in
            let trimmed = row.count > width ? Array(row.prefix(width)) : row
            return trimmed + Array(repeating: "", count: max(0, width - trimmed.count))
        }
        return (padded, isTruncated)
    }

    /// `t="s"` indexes the shared table; everything else is already the text,
    /// or a number this shows as written rather than reformatting.
    private static func resolve(value: String, type: String, sharedStrings: [String]) -> String {
        let text: String
        switch type {
        case "s":
            guard let index = Int(value), index >= 0, index < sharedStrings.count else { return "" }
            text = sharedStrings[index]
        case "b":
            text = value == "1" ? "TRUE" : "FALSE"
        case "e":
            text = value
        default:
            text = value
        }

        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard flattened.count > maximumCellLength else { return flattened }
        return String(flattened.prefix(maximumCellLength)) + "…"
    }

    /// "AB12" names column 27. A reference that is missing or unreadable falls
    /// back to the next free slot in the row.
    private static func column(fromReference reference: String, fallback: Int) -> Int {
        var value = 0
        var sawLetter = false
        for character in reference.uppercased() {
            guard let ascii = character.asciiValue else { break }
            guard ascii >= 65, ascii <= 90 else { break }
            value = value * 26 + Int(ascii - 64)
            sawLetter = true
            // Three letters reach column 18,278, far past the column cap.
            if value > 1 << 20 { return fallback }
        }
        return sawLetter ? value - 1 : fallback
    }
}
