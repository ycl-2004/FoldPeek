import Foundation

/// A forward-only scanner over the XML inside a document container.
///
/// This is deliberately not a general XML parser. It recognises elements,
/// attributes, character data, CDATA sections, comments, and the five
/// predefined entities — and nothing else. It has no DTD support and defines
/// no entities of its own, so the entity-expansion attacks that general parsers
/// must defend against have nothing here to expand. Unknown constructs are
/// skipped rather than interpreted.
///
/// It never resolves a reference, never fetches anything, and never acts on a
/// value it reads. Callers get tokens; what they mean is the caller's business.
struct XMLScanner {
    enum Token {
        case start(name: String, attributes: [String: String], isSelfClosing: Bool)
        case end(name: String)
        case text(String)
    }

    /// Caps the characters one element's text may contribute, so a single
    /// pathological run cannot grow without bound.
    static let maximumTextLength = 1 << 20

    private let scalars: [UInt8]
    private var index: Int

    init(_ data: Data) {
        scalars = [UInt8](data)
        index = 0
    }

    mutating func next() -> Token? {
        while index < scalars.count {
            if scalars[index] == UInt8(ascii: "<") {
                if let token = readMarkup() { return token }
                continue
            }
            if let token = readText() { return token }
        }
        return nil
    }

    // MARK: - Markup

    private mutating func readMarkup() -> Token? {
        let start = index
        index += 1  // consume '<'
        guard index < scalars.count else { return nil }

        switch scalars[index] {
        case UInt8(ascii: "?"):
            skipUntil(">")
            return nil
        case UInt8(ascii: "!"):
            return readDeclarationOrComment()
        case UInt8(ascii: "/"):
            index += 1
            let name = readName()
            skipUntil(">")
            return name.isEmpty ? nil : .end(name: name)
        default:
            break
        }

        let name = readName()
        guard !name.isEmpty else {
            index = start + 1
            return nil
        }

        var attributes: [String: String] = [:]
        var isSelfClosing = false

        while index < scalars.count {
            skipWhitespace()
            guard index < scalars.count else { break }

            if scalars[index] == UInt8(ascii: "/") {
                isSelfClosing = true
                index += 1
                continue
            }
            if scalars[index] == UInt8(ascii: ">") {
                index += 1
                break
            }

            let attributeName = readName()
            guard !attributeName.isEmpty else {
                // Not a name and not a terminator: step over it so a malformed
                // tag cannot stall the scan.
                index += 1
                continue
            }
            skipWhitespace()
            guard index < scalars.count, scalars[index] == UInt8(ascii: "=") else {
                attributes[attributeName] = ""
                continue
            }
            index += 1
            skipWhitespace()
            attributes[attributeName] = readQuotedValue()
        }

        return .start(name: name, attributes: attributes, isSelfClosing: isSelfClosing)
    }

    /// Comments, CDATA, and DOCTYPE. CDATA is the only one whose contents are
    /// kept; a DOCTYPE is skipped entirely, which is what makes an entity
    /// declaration a no-op here.
    private mutating func readDeclarationOrComment() -> Token? {
        if matches("!--") {
            index += 3
            while index + 2 < scalars.count {
                if scalars[index] == UInt8(ascii: "-"),
                   scalars[index + 1] == UInt8(ascii: "-"),
                    scalars[index + 2] == UInt8(ascii: ">") {
                    index += 3
                    return nil
                }
                index += 1
            }
            index = scalars.count
            return nil
        }

        if matches("[CDATA[") {
            index += 7
            let contentStart = index
            while index + 2 < scalars.count {
                if scalars[index] == UInt8(ascii: "]"),
                   scalars[index + 1] == UInt8(ascii: "]"),
                   scalars[index + 2] == UInt8(ascii: ">") {
                    let contentEnd = min(index, contentStart + Self.maximumTextLength)
                    let bytes = scalars[contentStart..<contentEnd]
                    index += 3
                    return bytes.isEmpty ? nil : .text(String(decoding: bytes, as: UTF8.self))
                }
                index += 1
            }

            let contentEnd = min(scalars.count, contentStart + Self.maximumTextLength)
            let bytes = scalars[contentStart..<contentEnd]
            index = scalars.count
            return bytes.isEmpty ? nil : .text(String(decoding: bytes, as: UTF8.self))
        }

        // A DOCTYPE may carry a bracketed internal subset; both it and the
        // declaration are stepped over without being read.
        var depth = 0
        while index < scalars.count {
            let byte = scalars[index]
            if byte == UInt8(ascii: "[") { depth += 1 }
            if byte == UInt8(ascii: "]") { depth -= 1 }
            if byte == UInt8(ascii: ">"), depth <= 0 {
                index += 1
                return nil
            }
            index += 1
        }
        return nil
    }

    // MARK: - Text

    private mutating func readText() -> Token? {
        var bytes: [UInt8] = []
        while index < scalars.count, scalars[index] != UInt8(ascii: "<") {
            if bytes.count < Self.maximumTextLength { bytes.append(scalars[index]) }
            index += 1
        }
        guard !bytes.isEmpty else { return nil }
        let raw = String(decoding: bytes, as: UTF8.self)
        return .text(Self.decodeEntities(in: raw))
    }

    /// Only the five predefined entities and numeric character references. An
    /// entity this does not know is left as written rather than looked up.
    static func decodeEntities(in text: String) -> String {
        guard text.contains("&") else { return text }

        var output = ""
        output.reserveCapacity(text.count)
        var rest = Substring(text)

        while let ampersand = rest.firstIndex(of: "&") {
            output.append(contentsOf: rest[rest.startIndex..<ampersand])
            let afterAmpersand = rest.index(after: ampersand)
            guard let semicolon = rest[afterAmpersand...].firstIndex(of: ";"),
                  rest.distance(from: afterAmpersand, to: semicolon) <= 10
            else {
                output.append("&")
                rest = rest[afterAmpersand...]
                continue
            }

            let body = rest[afterAmpersand..<semicolon]
            switch body {
            case "amp": output.append("&")
            case "lt": output.append("<")
            case "gt": output.append(">")
            case "quot": output.append("\"")
            case "apos": output.append("'")
            default:
                if body.hasPrefix("#"),
                   let scalar = numericScalar(body.dropFirst()) {
                    output.append(Character(scalar))
                } else {
                    output.append("&")
                    output.append(contentsOf: body)
                    output.append(";")
                }
            }
            rest = rest[rest.index(after: semicolon)...]
        }
        output.append(contentsOf: rest)
        return output
    }

    private static func numericScalar(_ body: Substring) -> Unicode.Scalar? {
        let isHex = body.hasPrefix("x") || body.hasPrefix("X")
        let digits = isHex ? body.dropFirst() : body
        guard !digits.isEmpty,
              let value = UInt32(digits, radix: isHex ? 16 : 10)
        else { return nil }
        return Unicode.Scalar(value)
    }

    // MARK: - Primitives

    private mutating func readName() -> String {
        var bytes: [UInt8] = []
        while index < scalars.count {
            let byte = scalars[index]
            let isNameByte = (byte >= 0x41 && byte <= 0x5A)
                || (byte >= 0x61 && byte <= 0x7A)
                || (byte >= 0x30 && byte <= 0x39)
                || byte == UInt8(ascii: ":") || byte == UInt8(ascii: "_")
                || byte == UInt8(ascii: "-") || byte == UInt8(ascii: ".")
                || byte >= 0x80
            guard isNameByte else { break }
            bytes.append(byte)
            index += 1
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private mutating func readQuotedValue() -> String {
        guard index < scalars.count else { return "" }
        let quote = scalars[index]
        guard quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") else { return "" }
        index += 1

        var bytes: [UInt8] = []
        while index < scalars.count, scalars[index] != quote {
            if bytes.count < Self.maximumTextLength { bytes.append(scalars[index]) }
            index += 1
        }
        if index < scalars.count { index += 1 }
        return Self.decodeEntities(in: String(decoding: bytes, as: UTF8.self))
    }

    private mutating func skipWhitespace() {
        while index < scalars.count, scalars[index] <= 0x20 { index += 1 }
    }

    private mutating func skipUntil(_ terminator: Character) {
        let byte = terminator.asciiValue ?? UInt8(ascii: ">")
        while index < scalars.count, scalars[index] != byte { index += 1 }
        if index < scalars.count { index += 1 }
    }

    private func matches(_ prefix: String) -> Bool {
        let bytes = Array(prefix.utf8)
        guard index + bytes.count <= scalars.count else { return false }
        for (offset, byte) in bytes.enumerated() where scalars[index + offset] != byte {
            return false
        }
        return true
    }
}
