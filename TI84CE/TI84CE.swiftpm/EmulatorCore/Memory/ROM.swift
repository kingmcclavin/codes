import Foundation

/// A validated TI-84 Plus CE flash image ("ROM dump").
///
/// The image is treated as read-only input: the emulator copies it into the emulated
/// flash chip, and anything the calculator OS later programs into flash (archive,
/// apps) lives in that copy, never in the original file.
public struct ROMImage {
    public enum LoadError: Error, CustomStringConvertible {
        case notFound
        case unreadable(String)
        case badSize(Int)
        case notEZ80

        public var description: String {
            switch self {
            case .notFound: return "No ROM image was found."
            case .unreadable(let why): return "The ROM image could not be read: \(why)"
            case .badSize(let n): return "Unexpected ROM size \(n) bytes (a TI-84 Plus CE dump is 4 MiB)."
            case .notEZ80: return "This image does not start with eZ80 boot code; it does not look like a TI-84 Plus CE ROM."
            }
        }
    }

    public static let flashSize = 0x400000

    public let data: [UInt8]
    public let sha256: String
    public let bootVersion: String?
    public let osVersion: String?

    public init(data bytes: [UInt8]) throws {
        // Accept a full 4 MiB dump. Smaller dumps (boot + OS only) are padded with
        // erased flash (0xFF), which is what an unwritten flash sector reads as.
        guard bytes.count >= 0x20000, bytes.count <= ROMImage.flashSize else { throw LoadError.badSize(bytes.count) }
        var image = bytes
        if image.count < ROMImage.flashSize { image += [UInt8](repeating: 0xFF, count: ROMImage.flashSize - image.count) }
        // The CE boot code starts with DI (F3); the reset vector is executed in Z80 mode.
        guard image[0] == 0xF3 else { throw LoadError.notEZ80 }
        data = image
        sha256 = SHA256.hexDigest(image)
        bootVersion = ROMImage.findVersion(in: image, range: 0..<0x20000)
        osVersion = ROMImage.findVersion(in: image, range: 0x20000..<0x100000)
    }

    public init(contentsOf url: URL) throws {
        let d: Data
        do { d = try Data(contentsOf: url) } catch { throw LoadError.unreadable(error.localizedDescription) }
        try self.init(data: [UInt8](d))
    }

    /// Finds the first "d.d.d.dddd" version string in a range of the image.
    static func findVersion(in image: [UInt8], range: Range<Int>) -> String? {
        let digit: (UInt8) -> Bool = { $0 >= 0x30 && $0 <= 0x39 }
        let dot: UInt8 = 0x2E
        var i = range.lowerBound
        while i + 10 <= range.upperBound {
            if digit(image[i]), image[i + 1] == dot, digit(image[i + 2]), image[i + 3] == dot,
               digit(image[i + 4]), image[i + 5] == dot,
               digit(image[i + 6]), digit(image[i + 7]), digit(image[i + 8]), digit(image[i + 9]) {
                return String(decoding: image[i..<i + 10], as: UTF8.self)
            }
            i += 1
        }
        return nil
    }

    public var summary: String {
        "ROM \(data.count / 1024) KiB, boot \(bootVersion ?? "?"), OS \(osVersion ?? "?"), sha256 \(sha256.prefix(16))…"
    }
}
