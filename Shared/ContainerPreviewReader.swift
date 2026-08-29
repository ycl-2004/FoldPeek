import AppKit
import Compression
import Foundation
import ImageIO

/// Recovers the preview image a document container already carries.
///
/// Pages, Keynote, Numbers, and some Office files are ZIP containers that store
/// a rendered picture of their own first page. Reading that picture needs no
/// document parser and no help from any other process — which matters, because
/// the system thumbnail service cannot be handed a file that a sandboxed
/// extension reached through Quick Look's own grant.
///
/// This reader is deliberately narrow. It locates entries by exact name, reads
/// only those bytes, inflates at most one of them, and hands the result to
/// ImageIO. It never walks the archive's contents, never writes anything to
/// disk, and never follows a path stored inside the file.
enum ContainerPreviewReader {
    /// Entry names worth looking for, best picture first.
    private static let candidates = [
        // iWork — a full-size render of page one, almost always stored uncompressed.
        "preview.jpg",
        "QuickLook/Thumbnail.jpg",
        "preview-web.jpg",
        // Office Open XML — present only when the authoring app chose to save it.
        "docProps/thumbnail.jpeg",
        "docProps/thumbnail.jpg",
        "docProps/thumbnail.png"
    ]

    /// The containers worth opening. Anything else is not a ZIP document.
    private static let extensions: Set<String> = [
        "pages", "key", "numbers", "pptx", "docx", "xlsx", "ppsx", "odp", "ods", "odt"
    ]

    /// Caps the entry inflated into memory.
    static let maximumEntryBytes = 32 * 1024 * 1024
    /// Caps the central directory read while hunting for an entry name.
    private static let maximumDirectoryBytes = 4 * 1024 * 1024
    /// How far back from the end the end-of-central-directory record is sought.
    private static let maximumTrailerBytes = 66 * 1024

    static func handles(pathExtension: String) -> Bool {
        extensions.contains(pathExtension.lowercased())
    }

    static func embeddedPreview(at url: URL) -> NSImage? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let directory = try? centralDirectory(in: handle) else { return nil }
        for name in candidates {
            guard let entry = locate(name: name, in: directory) else { continue }
            guard let data = read(entry, from: handle) else { continue }
            if let image = decode(data) { return image }
        }
        return nil
    }

    // MARK: - Archive structure

    private struct Entry {
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: UInt64
    }

    /// Finds the end-of-central-directory record and returns the directory itself.
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

    /// Walks the central directory for one exact entry name.
    private static func locate(name: String, in directory: Data) -> Entry? {
        guard let wanted = name.data(using: .utf8) else { return nil }
        var cursor = 0

        while cursor + 46 <= directory.count {
            guard readUInt32(directory, at: cursor) == 0x0201_4B50 else { return nil }

            let nameLength = Int(readUInt16(directory, at: cursor + 28))
            let extraLength = Int(readUInt16(directory, at: cursor + 30))
            let commentLength = Int(readUInt16(directory, at: cursor + 32))
            let nameStart = cursor + 46
            guard nameStart + nameLength <= directory.count else { return nil }

            if nameLength == wanted.count,
               directory[(directory.startIndex + nameStart)..<(directory.startIndex + nameStart + nameLength)]
                .elementsEqual(wanted) {
                let compressed = Int(readUInt32(directory, at: cursor + 20))
                let uncompressed = Int(readUInt32(directory, at: cursor + 24))
                // A 0xFFFFFFFF field means ZIP64, which this reader does not decode.
                guard compressed >= 0, compressed < maximumEntryBytes,
                      uncompressed >= 0, uncompressed <= maximumEntryBytes
                else { return nil }
                return Entry(
                    compressionMethod: readUInt16(directory, at: cursor + 10),
                    compressedSize: compressed,
                    uncompressedSize: uncompressed,
                    localHeaderOffset: UInt64(readUInt32(directory, at: cursor + 42))
                )
            }

            cursor = nameStart + nameLength + extraLength + commentLength
        }
        return nil
    }

    /// Reads one entry's bytes, inflating them only when the entry is deflated.
    private static func read(_ entry: Entry, from handle: FileHandle) -> Data? {
        // The local header repeats the name and extra lengths, and only it
        // gives the true offset of the data.
        guard (try? handle.seek(toOffset: entry.localHeaderOffset)) != nil,
              let header = try? handle.read(upToCount: 30),
              header.count == 30,
              readUInt32(header, at: 0) == 0x0403_4B50
        else { return nil }

        let nameLength = Int(readUInt16(header, at: 26))
        let extraLength = Int(readUInt16(header, at: 28))
        let dataOffset = entry.localHeaderOffset + 30 + UInt64(nameLength) + UInt64(extraLength)

        guard (try? handle.seek(toOffset: dataOffset)) != nil,
              let payload = try? handle.read(upToCount: entry.compressedSize),
              payload.count == entry.compressedSize
        else { return nil }

        switch entry.compressionMethod {
        case 0:
            return payload
        case 8:
            return inflate(payload, to: entry.uncompressedSize)
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

    // MARK: - Decoding

    /// The recovered bytes are an image and nothing else, so they go through
    /// the same capped ImageIO path as any other picture.
    private static func decode(_ data: Data) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: FilePreviewLoader.maximumImagePixelSize,
            kCGImageSourceShouldCache: false
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
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
