import Foundation
import Compression

/// A minimal, read-only ZIP archive reader.
///
/// Swift Playgrounds / iPadOS does **not** ship a public ZIP container API in
/// Foundation, so we parse the ZIP structure ourselves and use the system
/// `Compression` framework (fully available to a sandboxed app) to inflate
/// DEFLATE-compressed entries. An `.ipa` is just a ZIP, so this is all we need
/// to read `Info.plist`, icons, the Mach-O header, and `PlugIns/` listings.
///
/// Scope / honesty:
///  - Supports STORE (method 0) and DEFLATE (method 8) — the only methods IPAs use.
///  - Detects ZIP64 and reports it clearly instead of silently misreading.
///  - This is a *reader*; we never need to write ZIPs.
final class MiniZip {

    struct Entry {
        let path: String
        let compressionMethod: UInt16
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let localHeaderOffset: UInt64
        var isDirectory: Bool { path.hasSuffix("/") }
    }

    enum ZipError: LocalizedError {
        case notReadable
        case eocdNotFound
        case corrupt(String)
        case zip64Unsupported
        case unsupportedCompression(UInt16)
        case inflateFailed

        var errorDescription: String? {
            switch self {
            case .notReadable: return "The archive could not be read."
            case .eocdNotFound: return "Not a valid ZIP/IPA (no end-of-central-directory record)."
            case .corrupt(let w): return "The archive appears corrupt: \(w)"
            case .zip64Unsupported: return "This archive uses the ZIP64 format, which this reader does not support."
            case .unsupportedCompression(let m): return "Unsupported ZIP compression method \(m)."
            case .inflateFailed: return "Failed to decompress an entry."
            }
        }
    }

    private let data: Data
    let entries: [Entry]

    init(url: URL) throws {
        guard let d = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            throw ZipError.notReadable
        }
        self.data = d
        self.entries = try MiniZip.readCentralDirectory(d)
    }

    // MARK: Lookup

    func entry(atPath path: String) -> Entry? {
        entries.first { $0.path == path }
    }

    func firstEntry(where predicate: (Entry) -> Bool) -> Entry? {
        entries.first(where: predicate)
    }

    func entries(withPrefix prefix: String) -> [Entry] {
        entries.filter { $0.path.hasPrefix(prefix) }
    }

    // MARK: Extraction

    func extract(_ entry: Entry) throws -> Data {
        // Re-read the local file header to find the true data offset: the extra
        // field length in the local header can differ from the central directory.
        let lho = Int(entry.localHeaderOffset)
        guard lho + 30 <= data.count else { throw ZipError.corrupt("local header out of range") }
        let sig = readUInt32(at: lho)
        guard sig == 0x04034b50 else { throw ZipError.corrupt("bad local header signature") }
        let nameLen = Int(readUInt16(at: lho + 26))
        let extraLen = Int(readUInt16(at: lho + 28))
        let dataStart = lho + 30 + nameLen + extraLen
        let compSize = Int(entry.compressedSize)
        guard dataStart + compSize <= data.count else {
            throw ZipError.corrupt("entry data out of range")
        }
        let compressed = data.subdata(in: dataStart..<(dataStart + compSize))

        switch entry.compressionMethod {
        case 0:
            return compressed
        case 8:
            return try inflate(compressed, expectedSize: Int(entry.uncompressedSize))
        default:
            throw ZipError.unsupportedCompression(entry.compressionMethod)
        }
    }

    func extractData(atPath path: String) throws -> Data? {
        guard let e = entry(atPath: path) else { return nil }
        return try extract(e)
    }

    // MARK: DEFLATE

    private func inflate(_ input: Data, expectedSize: Int) throws -> Data {
        // Empty payloads inflate to empty.
        if input.isEmpty { return Data() }
        // Allocate at least expectedSize; grow if the header lied.
        var capacity = max(expectedSize, input.count * 4, 1024)
        for _ in 0..<6 {
            let result: Data? = input.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Data? in
                guard let srcBase = src.baseAddress else { return nil }
                let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
                defer { dst.deallocate() }
                let written = compression_decode_buffer(
                    dst, capacity,
                    srcBase.assumingMemoryBound(to: UInt8.self), input.count,
                    nil, COMPRESSION_ZLIB)
                if written == 0 { return nil }
                // If we exactly filled the buffer the output may be truncated;
                // signal caller to retry with a larger buffer.
                if written == capacity && expectedSize == 0 { return nil }
                return Data(bytes: dst, count: written)
            }
            if let result { return result }
            capacity *= 2
        }
        throw ZipError.inflateFailed
    }

    // MARK: Central directory parsing

    private static func readCentralDirectory(_ data: Data) throws -> [Entry] {
        let n = data.count
        guard n >= 22 else { throw ZipError.eocdNotFound }

        // Scan backwards for the EOCD signature (0x06054b50), allowing for a
        // trailing comment of up to 64 KiB.
        let maxComment = min(n - 22, 65_557)
        var eocd = -1
        var i = n - 22
        let lowerBound = n - 22 - maxComment
        while i >= max(0, lowerBound) {
            if data[i] == 0x50, data[i+1] == 0x4b, data[i+2] == 0x05, data[i+3] == 0x06 {
                eocd = i
                break
            }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.eocdNotFound }

        func u16(_ off: Int) -> UInt16 {
            UInt16(data[off]) | (UInt16(data[off+1]) << 8)
        }
        func u32(_ off: Int) -> UInt32 {
            UInt32(data[off]) | (UInt32(data[off+1]) << 8)
                | (UInt32(data[off+2]) << 16) | (UInt32(data[off+3]) << 24)
        }

        let totalEntries = Int(u16(eocd + 10))
        let cdSize = Int(u32(eocd + 12))
        let cdOffset = Int(u32(eocd + 16))

        // ZIP64 sentinel values.
        if cdOffset == 0xFFFFFFFF || cdSize == 0xFFFFFFFF || u16(eocd + 10) == 0xFFFF {
            throw ZipError.zip64Unsupported
        }
        guard cdOffset + cdSize <= n else { throw ZipError.corrupt("central dir out of range") }

        var entries: [Entry] = []
        entries.reserveCapacity(totalEntries)
        var p = cdOffset
        let cdEnd = cdOffset + cdSize

        while p + 46 <= cdEnd {
            let sig = u32(p)
            guard sig == 0x02014b50 else { break }
            let method = u16(p + 10)
            let compSize = UInt64(u32(p + 20))
            let uncompSize = UInt64(u32(p + 24))
            let nameLen = Int(u16(p + 28))
            let extraLen = Int(u16(p + 30))
            let commentLen = Int(u16(p + 32))
            let localOffset = UInt64(u32(p + 42))

            if compSize == 0xFFFFFFFF || uncompSize == 0xFFFFFFFF || localOffset == 0xFFFFFFFF {
                throw ZipError.zip64Unsupported
            }

            let nameStart = p + 46
            guard nameStart + nameLen <= cdEnd else { throw ZipError.corrupt("name out of range") }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLen))
            let name = String(decoding: nameData, as: UTF8.self)

            entries.append(Entry(path: name,
                                 compressionMethod: method,
                                 compressedSize: compSize,
                                 uncompressedSize: uncompSize,
                                 localHeaderOffset: localOffset))
            p = nameStart + nameLen + extraLen + commentLen
        }
        return entries
    }

    // MARK: Byte helpers

    private func readUInt16(at off: Int) -> UInt16 {
        UInt16(data[off]) | (UInt16(data[off+1]) << 8)
    }
    private func readUInt32(at off: Int) -> UInt32 {
        UInt32(data[off]) | (UInt32(data[off+1]) << 8)
            | (UInt32(data[off+2]) << 16) | (UInt32(data[off+3]) << 24)
    }
}
