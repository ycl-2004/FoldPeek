import AppKit

/// How a source file is coloured.
///
/// Nothing here parses the file as a document format. The highlighter is a
/// single-pass character scanner over text that has already been read and
/// capped: it recognises comments, strings, numbers, words, and brackets, and
/// assigns colours we choose. It never interprets markup, never resolves a
/// reference, and never reaches outside the string it was handed. Scanning is
/// deliberately hand-written rather than regular-expression based, so no input
/// can drive it into backtracking.
struct CodeLanguage {
    let lineComment: [String]
    let blockComment: (open: String, close: String)?
    let stringDelimiters: Set<unichar>
    let keywords: Set<String>
    /// Python-style triple quotes, which span lines.
    let hasTripleQuotes: Bool
    /// Colour a string as a key when a colon follows it, as in JSON.
    let highlightsObjectKeys: Bool

    static func detect(pathExtension: String) -> CodeLanguage? {
        switch pathExtension.lowercased() {
        case "swift":
            return CodeLanguage(
                lineComment: ["//"], blockComment: ("/*", "*/"),
                stringDelimiters: ["\"".utf16Unit], keywords: swiftKeywords,
                hasTripleQuotes: false, highlightsObjectKeys: false
            )
        case "py", "pyw":
            return CodeLanguage(
                lineComment: ["#"], blockComment: nil,
                stringDelimiters: ["\"".utf16Unit, "'".utf16Unit], keywords: pythonKeywords,
                hasTripleQuotes: true, highlightsObjectKeys: false
            )
        case "js", "jsx", "ts", "tsx", "mjs", "cjs":
            return CodeLanguage(
                lineComment: ["//"], blockComment: ("/*", "*/"),
                stringDelimiters: ["\"".utf16Unit, "'".utf16Unit, "`".utf16Unit],
                keywords: javaScriptKeywords, hasTripleQuotes: false, highlightsObjectKeys: true
            )
        case "json", "ipynb", "jsonc", "geojson":
            return CodeLanguage(
                lineComment: ["//"], blockComment: nil,
                stringDelimiters: ["\"".utf16Unit], keywords: jsonKeywords,
                hasTripleQuotes: false, highlightsObjectKeys: true
            )
        case "c", "h", "cpp", "cc", "hpp", "m", "mm", "java", "cs", "go", "rs", "kt", "scala", "php":
            return CodeLanguage(
                lineComment: ["//"], blockComment: ("/*", "*/"),
                stringDelimiters: ["\"".utf16Unit, "'".utf16Unit], keywords: cFamilyKeywords,
                hasTripleQuotes: false, highlightsObjectKeys: false
            )
        case "sh", "bash", "zsh", "fish", "command":
            return CodeLanguage(
                lineComment: ["#"], blockComment: nil,
                stringDelimiters: ["\"".utf16Unit, "'".utf16Unit], keywords: shellKeywords,
                hasTripleQuotes: false, highlightsObjectKeys: false
            )
        case "yml", "yaml", "toml", "ini", "cfg", "conf":
            return CodeLanguage(
                lineComment: ["#"], blockComment: nil,
                stringDelimiters: ["\"".utf16Unit, "'".utf16Unit], keywords: [],
                hasTripleQuotes: false, highlightsObjectKeys: true
            )
        case "css", "scss", "less":
            return CodeLanguage(
                lineComment: ["//"], blockComment: ("/*", "*/"),
                stringDelimiters: ["\"".utf16Unit, "'".utf16Unit], keywords: [],
                hasTripleQuotes: false, highlightsObjectKeys: false
            )
        case "html", "htm", "xml", "svg", "plist":
            // Coloured as text with brackets and strings — never rendered.
            return CodeLanguage(
                lineComment: [], blockComment: ("<!--", "-->"),
                stringDelimiters: ["\"".utf16Unit, "'".utf16Unit], keywords: [],
                hasTripleQuotes: false, highlightsObjectKeys: false
            )
        default:
            return nil
        }
    }

    private static let swiftKeywords: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import",
        "init", "inout", "internal", "let", "open", "operator", "private", "protocol", "public",
        "rethrows", "static", "struct", "subscript", "typealias", "var", "break", "case", "continue",
        "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat",
        "return", "switch", "where", "while", "as", "catch", "false", "is", "nil", "super", "self",
        "Self", "throw", "throws", "true", "try", "async", "await", "actor", "some", "any", "final",
        "lazy", "override", "required", "weak", "unowned", "mutating", "nonmutating", "indirect"
    ]
    private static let pythonKeywords: Set<String> = [
        "False", "None", "True", "and", "as", "assert", "async", "await", "break", "class",
        "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global",
        "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return",
        "try", "while", "with", "yield", "self", "match", "case"
    ]
    private static let javaScriptKeywords: Set<String> = [
        "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger",
        "default", "delete", "do", "else", "export", "extends", "finally", "for", "function",
        "if", "import", "in", "instanceof", "let", "new", "of", "return", "static", "super",
        "switch", "this", "throw", "try", "typeof", "var", "void", "while", "with", "yield",
        "true", "false", "null", "undefined", "interface", "type", "enum", "implements", "readonly"
    ]
    private static let jsonKeywords: Set<String> = ["true", "false", "null"]
    private static let cFamilyKeywords: Set<String> = [
        "auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else",
        "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long", "register",
        "return", "short", "signed", "sizeof", "static", "struct", "switch", "typedef", "union",
        "unsigned", "void", "volatile", "while", "class", "public", "private", "protected",
        "namespace", "template", "typename", "virtual", "new", "delete", "this", "true", "false",
        "nullptr", "func", "package", "import", "type", "var", "let", "fn", "impl", "trait",
        "match", "pub", "mut", "use", "mod", "self", "null", "final", "abstract", "interface"
    ]
    private static let shellKeywords: Set<String> = [
        "if", "then", "else", "elif", "fi", "case", "esac", "for", "while", "until", "do", "done",
        "function", "in", "select", "time", "return", "export", "local", "readonly", "declare",
        "set", "unset", "source", "echo", "cd", "exit"
    ]
}

enum CodeHighlighter {
    /// Beyond this, colouring is skipped and the text is shown plain. Layout,
    /// not scanning, is the cost that matters at this size.
    static let maximumHighlightCharacters = 200_000

    /// Returns coloured text, or nil when the file is not a recognised
    /// language or is too large to colour.
    static func highlight(text: String, pathExtension: String, font: NSFont) -> NSAttributedString? {
        guard let language = CodeLanguage.detect(pathExtension: pathExtension) else { return nil }
        let source = text as NSString
        guard source.length > 0, source.length <= maximumHighlightCharacters else { return nil }

        var units = [unichar](repeating: 0, count: source.length)
        source.getCharacters(&units, range: NSRange(location: 0, length: source.length))

        let result = NSMutableAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: PaperTheme.Syntax.plain]
        )
        result.beginEditing()
        for span in scan(units: units, language: language) {
            result.addAttribute(.foregroundColor, value: span.color, range: span.range)
        }
        result.endEditing()
        return result
    }

    private struct Span {
        let range: NSRange
        let color: NSColor
    }

    // MARK: - Scanner

    private static func scan(units: [unichar], language: CodeLanguage) -> [Span] {
        var spans: [Span] = []
        var index = 0
        var bracketDepth = 0
        let length = units.count

        let lineComments = language.lineComment.map { Array($0.utf16) }
        let blockOpen = language.blockComment.map { Array($0.open.utf16) }
        let blockClose = language.blockComment.map { Array($0.close.utf16) }

        while index < length {
            let unit = units[index]

            if let start = matchedLineComment(units, index, lineComments) {
                let end = scanToLineEnd(units, from: start)
                spans.append(Span(range: NSRange(location: index, length: end - index), color: PaperTheme.Syntax.comment))
                index = end
                continue
            }

            if let open = blockOpen, let close = blockClose, matches(units, open, at: index) {
                let end = scanBlockComment(units, from: index + open.count, close: close)
                spans.append(Span(range: NSRange(location: index, length: end - index), color: PaperTheme.Syntax.comment))
                index = end
                continue
            }

            if language.stringDelimiters.contains(unit) {
                let end = scanString(units, from: index, delimiter: unit, allowsTriple: language.hasTripleQuotes)
                let isKey = language.highlightsObjectKeys && colonFollows(units, from: end)
                spans.append(Span(
                    range: NSRange(location: index, length: end - index),
                    color: isKey ? PaperTheme.Syntax.key : PaperTheme.Syntax.string
                ))
                index = end
                continue
            }

            if isDigit(unit) || (unit == dash && index + 1 < length && isDigit(units[index + 1]) && !isIdentifierBody(previous(units, index))) {
                let end = scanNumber(units, from: index)
                spans.append(Span(range: NSRange(location: index, length: end - index), color: PaperTheme.Syntax.number))
                index = end
                continue
            }

            if isIdentifierStart(unit) {
                var end = index + 1
                while end < length, isIdentifierBody(units[end]) { end += 1 }
                if end - index <= 24, !language.keywords.isEmpty {
                    let word = String(utf16CodeUnits: Array(units[index..<end]), count: end - index)
                    if language.keywords.contains(word) {
                        spans.append(Span(range: NSRange(location: index, length: end - index), color: PaperTheme.Syntax.keyword))
                    }
                }
                index = end
                continue
            }

            if isOpenBracket(unit) {
                spans.append(Span(range: NSRange(location: index, length: 1), color: bracketColor(bracketDepth)))
                bracketDepth += 1
                index += 1
                continue
            }

            if isCloseBracket(unit) {
                bracketDepth = max(0, bracketDepth - 1)
                spans.append(Span(range: NSRange(location: index, length: 1), color: bracketColor(bracketDepth)))
                index += 1
                continue
            }

            index += 1
        }

        return spans
    }

    private static func bracketColor(_ depth: Int) -> NSColor {
        let palette = PaperTheme.Syntax.bracketDepths
        return palette[depth % palette.count]
    }

    // MARK: - Token scanners

    private static func matchedLineComment(_ units: [unichar], _ index: Int, _ tokens: [[unichar]]) -> Int? {
        for token in tokens where matches(units, token, at: index) {
            return index + token.count
        }
        return nil
    }

    private static func scanToLineEnd(_ units: [unichar], from start: Int) -> Int {
        var index = start
        while index < units.count, units[index] != newline { index += 1 }
        return index
    }

    private static func scanBlockComment(_ units: [unichar], from start: Int, close: [unichar]) -> Int {
        var index = start
        while index < units.count {
            if matches(units, close, at: index) { return index + close.count }
            index += 1
        }
        return units.count
    }

    private static func scanString(
        _ units: [unichar],
        from start: Int,
        delimiter: unichar,
        allowsTriple: Bool
    ) -> Int {
        let length = units.count
        let isTriple = allowsTriple
            && start + 2 < length
            && units[start + 1] == delimiter
            && units[start + 2] == delimiter

        var index = start + (isTriple ? 3 : 1)
        while index < length {
            let unit = units[index]
            if unit == backslash {
                index += 2
                continue
            }
            if isTriple {
                if unit == delimiter, index + 2 < length, units[index + 1] == delimiter, units[index + 2] == delimiter {
                    return index + 3
                }
            } else {
                if unit == delimiter { return index + 1 }
                // An unterminated single-line string stops at the newline
                // rather than swallowing the rest of the file.
                if unit == newline { return index }
            }
            index += 1
        }
        return length
    }

    private static func scanNumber(_ units: [unichar], from start: Int) -> Int {
        var index = start
        if units[index] == dash { index += 1 }
        while index < units.count {
            let unit = units[index]
            if isDigit(unit) || unit == dot || isHexLetter(unit) || unit == underscore {
                index += 1
            } else if (unit == plus || unit == dash),
                      index > start,
                      units[index - 1] == eLower || units[index - 1] == eUpper {
                index += 1
            } else {
                break
            }
        }
        return index
    }

    private static func colonFollows(_ units: [unichar], from index: Int) -> Bool {
        var probe = index
        while probe < units.count, isSpace(units[probe]) { probe += 1 }
        return probe < units.count && units[probe] == colon
    }

    private static func previous(_ units: [unichar], _ index: Int) -> unichar {
        index > 0 ? units[index - 1] : space
    }

    private static func matches(_ units: [unichar], _ token: [unichar], at index: Int) -> Bool {
        guard !token.isEmpty, index + token.count <= units.count else { return false }
        for offset in 0..<token.count where units[index + offset] != token[offset] {
            return false
        }
        return true
    }

    // MARK: - Character classes

    private static let newline: unichar = 10
    private static let space: unichar = 32
    private static let backslash: unichar = 92
    private static let underscore: unichar = 95
    private static let dot: unichar = 46
    private static let dash: unichar = 45
    private static let plus: unichar = 43
    private static let colon: unichar = 58
    private static let eLower: unichar = 101
    private static let eUpper: unichar = 69

    private static func isDigit(_ unit: unichar) -> Bool { unit >= 48 && unit <= 57 }
    private static func isSpace(_ unit: unichar) -> Bool { unit == 32 || unit == 9 || unit == 10 || unit == 13 }
    private static func isHexLetter(_ unit: unichar) -> Bool {
        (unit >= 97 && unit <= 102) || (unit >= 65 && unit <= 70) || unit == 120 || unit == 88
    }
    private static func isIdentifierStart(_ unit: unichar) -> Bool {
        (unit >= 97 && unit <= 122) || (unit >= 65 && unit <= 90) || unit == underscore || unit == 36
    }
    private static func isIdentifierBody(_ unit: unichar) -> Bool {
        isIdentifierStart(unit) || isDigit(unit)
    }
    private static func isOpenBracket(_ unit: unichar) -> Bool {
        unit == 40 || unit == 91 || unit == 123
    }
    private static func isCloseBracket(_ unit: unichar) -> Bool {
        unit == 41 || unit == 93 || unit == 125
    }
}

private extension String {
    /// The single UTF-16 unit of a one-character ASCII literal.
    var utf16Unit: unichar { Array(utf16)[0] }
}
