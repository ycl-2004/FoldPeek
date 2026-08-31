import Compression
import Foundation

/// A bounded, read-only reader for the ZIP containers that document formats are
/// built on.
///
/// It reads the central directory once, keeps the entry table in memory, and
/// fetches an entry's bytes only when asked for by name. Nothing is written,
/// no path stored inside the archive is ever acted on, and every dimension the
/// file controls — directory size, entry count, entry size — is capped before
/// any allocation follows from it.
final class ZipArchive {
    /// Caps the entry table built from one archive.
    static let maximumEntryCount = 8_192
    /// Caps a single entry inflated into memory.
    static let maximumEntryBytes = 32 * 1024 * 1024
    /// Caps the central directory read while building the entry table.
    static let maximumDirectoryBytes = 8 * 1024 * 1024
    /// How far back from the end the end-of-central-directory record is sought.
    private static let maximumTrailerBytes = 66 * 1024

    private struct Entry {
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: UInt64
    }

    private let handle: FileHandle
    private var entries: [String: Entry]
    /// Entry names in the order the directory lists them.
    let names: [String]

    // MARK: - Opening

    init?(url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        guard let directory = try? Self.centralDirectory(in: handle) else {
            try? handle.close()
            return nil
        }
        let table = Self.entryTable(in: directory)
        guard !table.names.isEmpty else {
            try? handle.close()
            return nil
        }
        self.handle = handle
        entries = table.entries
        names = table.names
    }

    deinit {
        try? handle.close()
    }

    // MARK: - Reading

    func contains(_ name: String) -> Bool {
        entries[name] != nil
    }

    /// The entry's bytes, inflated when the archive stored it deflated.
    func data(for name: String) -> Data? {
        guard let entry = entries[name] else { return nil }

        // The local header repeats the name and extra lengths, and only it
        // gives the true offset of the data.
        guard (try? handle.seek(toOffset: entry.localHeaderOffset)) != nil,
              let header = try? handle.read(upToCount: 30),
              header.count == 30,
              Self.readUInt32(header, at: 0) == 0x0403_4B50
        else { return nil }

        let nameLength = Int(Self.readUInt16(header, at: 26))
        let extraLength = Int(Self.readUInt16(header, at: 28))
        let dataOffset = entry.localHeaderOffset + 30 + UInt64(nameLength) + UInt64(extraLength)

        guard (try? handle.seek(toOffset: dataOffset)) != nil,
              let payload = try? handle.read(upToCount: entry.compressedSize),
              payload.count == entry.compressedSize
        else { return nil }

        switch entry.compressionMethod {
        case 0:
            return payload
        case 8:
            return Self.inflate(payload, to: entry.uncompressedSize)
        default:
            return nil
        }
    }

    /// Raw DEFLATE, which is what `COMPRESSION_ZLIB` decodes when handed a
    /// buffer with no zlib wrapper — the form ZIP stores.
    private static func inflate(_ payload: Data, to capacity: Int) -> Data? {
        guard capacity > 0, capacity <= maximumEntryBytes else { return nil }

        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress else {
                return 0
            }
            return payload.withUnsafeBytes { source -> Int in
                guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    destinationBase, capacity,
                    sourceBase, payload.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }

        guard written > 0 else { return nil }
        return output.prefix(written)
    }

    // MARK: - Archive structure

    private static func centralDirectory(in handle: FileHandle) throws -> Data {
        let fileSize = try handle.seekToEnd()
        guard fileSize > 22 else { throw ReadError.malformed }

        let trailerLength = Int(min(fileSize, UInt64(maximumTrailerBytes)))
        try handle.seek(toOffset: fileSize - UInt64(trailerLength))
        guard let trailer = try handle.read(upToCount: trailerLength),
              trailer.count >= 22
        else { throw ReadError.malformed }

        // The record ends the file, but a trailing comment can push it back, so
        // the signature is searched for from the end.
        var recordStart: Int?
        var index = trailer.count - 22
        while index >= 0 {
            if trailer[trailer.startIndex + index] == 0x50,
               readUInt32(trailer, at: index) == 0x0605_4B50 {
                recordStart = index
                break
            }
            index -= 1
        }
        guard let recordStart else { throw ReadError.malformed }

        let directorySize = Int(readUInt32(trailer, at: recordStart + 12))
        let directoryOffset = UInt64(readUInt32(trailer, at: recordStart + 16))
        guard directorySize > 0,
              directorySize <= maximumDirectoryBytes,
              directoryOffset < fileSize
        else { throw ReadError.unsupported }

        try handle.seek(toOffset: directoryOffset)
        guard let directory = try handle.read(upToCount: directorySize),
              directory.count == directorySize
        else { throw ReadError.malformed }
        return directory
    }

    /// Walks the central directory once and records every entry it can bound.
    private static func entryTable(in directory: Data) -> (entries: [String: Entry], names: [String]) {
        var entries: [String: Entry] = [:]
        var names: [String] = []
        var cursor = 0

        while cursor + 46 <= directory.count, names.count < maximumEntryCount {
            guard readUInt32(directory, at: cursor) == 0x0201_4B50 else { break }

            let nameLength = Int(readUInt16(directory, at: cursor + 28))
            let extraLength = Int(readUInt16(directory, at: cursor + 30))
            let commentLength = Int(readUInt16(directory, at: cursor + 32))
            let nameStart = cursor + 46
            guard nameLength > 0, nameStart + nameLength <= directory.count else { break }

            let compressed = Int(readUInt32(directory, at: cursor + 20))
            let uncompressed = Int(readUInt32(directory, at: cursor + 24))
            let nameData = directory[
                (directory.startIndex + nameStart)..<(directory.startIndex + nameStart + nameLength)
            ]

            // A 0xFFFFFFFF size or offset means ZIP64, which this reader does
            // not decode; such an entry is skipped rather than guessed at.
            if let name = String(data: nameData, encoding: .utf8),
               compressed >= 0, compressed <= maximumEntryBytes,
               uncompressed >= 0, uncompressed <= maximumEntryBytes,
               entries[name] == nil {
                entries[name] = Entry(
                    compressionMethod: readUInt16(directory, at: cursor + 10),
                    compressedSize: compressed,
                    uncompressedSize: uncompressed,
                    localHeaderOffset: UInt64(readUInt32(directory, at: cursor + 42))
                )
                names.append(name)
            }

            cursor = nameStart + nameLength + extraLength + commentLength
        }
        return (entries, names)
    }

    // MARK: - Little-endian field reads

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        let base = data.startIndex + offset
        guard base + 2 <= data.endIndex else { return 0 }
        return UInt16(data[base]) | (UInt16(data[base + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        let base = data.startIndex + offset
        guard base + 4 <= data.endIndex else { return 0 }
        return UInt32(data[base])
            | (UInt32(data[base + 1]) << 8)
            | (UInt32(data[base + 2]) << 16)
            | (UInt32(data[base + 3]) << 24)
    }

    private enum ReadError: Error {
        case malformed
        case unsupported
    }
}
