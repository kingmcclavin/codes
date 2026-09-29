import Foundation

/// Where to obtain a ROM image.
public enum ROMSource: Sendable {
    /// A resource bundled with this Swift package (Sources/TI84EmulatorCore/Resources).
    case bundled(name: String = "ti84rom", extension: String = "rom")
    /// A file on disk (for example one the user imported).
    case file(URL)
    /// Raw bytes already in memory.
    case data(Data)
}

public enum ROMError: Error, CustomStringConvertible, Equatable {
    case notFound(String)
    case unreadable(String)
    case invalidSize(Int)
    case unsupportedModel(String)
    case missingBootCode

    public var description: String {
        switch self {
        case let .notFound(what):
            return "ROM not found: \(what). Add a legally obtained TI-84 Plus ROM dump as "
                + "Sources/TI84EmulatorCore/Resources/ti84rom.rom (or set TI84_ROM_PATH)."
        case let .unreadable(reason):
            return "ROM could not be read: \(reason)"
        case let .invalidSize(size):
            return "ROM has an unexpected size of \(size) bytes. Expected 1 MB (TI-84 Plus) "
                + "or 2 MB (TI-84 Plus Silver Edition / TI-83 Plus Silver Edition)."
        case let .unsupportedModel(reason):
            return "Unsupported ROM: \(reason)"
        case .missingBootCode:
            return "The ROM's boot page is blank, so the calculator cannot start. "
                + "The dump is probably incomplete."
        }
    }
}

/// A validated, read-only ROM (Flash) dump.
///
/// The image itself is never modified: the emulated Flash chip works on its
/// own copy, so the OS can archive variables without touching the original.
public struct ROMImage: Sendable {
    public let bytes: [UInt8]
    public let profile: HardwareProfile
    public let sha256: String
    public let crc32: UInt32
    /// Non-fatal observations about the image (e.g. no OS installed).
    public let warnings: [String]

    public var model: CalculatorModel { profile.model }
    public var size: Int { bytes.count }

    /// Validates `data` and detects the calculator model.
    /// - Parameter model: overrides detection (2 MB images are ambiguous between
    ///   the TI-84 Plus SE and TI-83 Plus SE; the TI-84 Plus SE is assumed).
    public init(data: Data, model: CalculatorModel? = nil) throws {
        let bytes = [UInt8](data)
        let detected: CalculatorModel
        switch bytes.count {
        case 0x100000:
            detected = .ti84Plus
        case 0x200000:
            detected = .ti84PlusSE
        case 0x400000:
            throw ROMError.unsupportedModel(
                "4 MB images are TI-84 Plus CE / TI-83 Premium CE ROMs, which use an eZ80 CPU "
                + "and different hardware. This emulator targets the Z80-based TI-84 Plus.")
        case 0x80000:
            throw ROMError.unsupportedModel(
                "512 KB images are TI-83 Plus ROMs, whose ASIC differs from the TI-84 Plus.")
        default:
            throw ROMError.invalidSize(bytes.count)
        }
        let chosen = model ?? detected
        let profile = HardwareProfile.profile(for: chosen)
        guard profile.flashSize == bytes.count else {
            throw ROMError.unsupportedModel("\(chosen.rawValue) needs a \(profile.flashSize)-byte ROM, got \(bytes.count)")
        }

        let bootStart = profile.bootPage * MemoryBus.bankSize
        if bytes[bootStart..<(bootStart + MemoryBus.bankSize)].allSatisfy({ $0 == 0xFF }) {
            throw ROMError.missingBootCode
        }

        var warnings: [String] = []
        if bytes[0..<MemoryBus.bankSize].allSatisfy({ $0 == 0xFF }) {
            warnings.append("No operating system is installed in this ROM; the boot code will ask for one.")
        }

        self.bytes = bytes
        self.profile = profile
        self.sha256 = SHA256.hexDigest(bytes)
        self.crc32 = CRC32.checksum(bytes)
        self.warnings = warnings
    }
}

/// Locates and validates ROM images. Additional ROMs can be supplied through
/// any `ROMSource` without changes to the emulator.
public enum ROMLoader {
    /// Environment variable that overrides the bundled ROM (handy for tests
    /// and the command-line tool).
    public static let pathEnvironmentVariable = "TI84_ROM_PATH"

    public static func load(_ source: ROMSource = .bundled(), model: CalculatorModel? = nil) throws -> ROMImage {
        let data: Data
        switch source {
        case let .bundled(name, ext):
            if let override = ProcessInfo.processInfo.environment[pathEnvironmentVariable], !override.isEmpty {
                return try load(.file(URL(fileURLWithPath: override)), model: model)
            }
            guard let url = bundledURL(name: name, extension: ext) else {
                throw ROMError.notFound("\(name).\(ext) in the package resources")
            }
            data = try read(url)
        case let .file(url):
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ROMError.notFound(url.path)
            }
            data = try read(url)
        case let .data(bytes):
            data = bytes
        }
        return try ROMImage(data: data, model: model)
    }

    /// URL of the bundled ROM resource, if present.
    public static func bundledURL(name: String = "ti84rom", extension ext: String = "rom") -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources")
    }

    /// Whether a ROM is available without user interaction.
    public static var isBundledROMAvailable: Bool {
        if let override = ProcessInfo.processInfo.environment[pathEnvironmentVariable], !override.isEmpty {
            return FileManager.default.fileExists(atPath: override)
        }
        return bundledURL() != nil
    }

    private static func read(_ url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw ROMError.unreadable("\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

// MARK: - Checksums (debugging aids; kept dependency-free)

public enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

public enum SHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    public static func digest(_ message: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                           0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var data = message
        let bitLength = UInt64(message.count) * 8
        data.append(0x80)
        while data.count % 64 != 56 { data.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) { data.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift))) }

        var w = [UInt32](repeating: 0, count: 64)
        for chunk in stride(from: 0, to: data.count, by: 64) {
            for i in 0..<16 {
                let j = chunk + i * 4
                w[i] = UInt32(data[j]) << 24 | UInt32(data[j + 1]) << 16 | UInt32(data[j + 2]) << 8 | UInt32(data[j + 3])
            }
            for i in 16..<64 {
                let s0 = w[i - 15].rotatedRight(7) ^ w[i - 15].rotatedRight(18) ^ (w[i - 15] >> 3)
                let s1 = w[i - 2].rotatedRight(17) ^ w[i - 2].rotatedRight(19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let s1 = e.rotatedRight(6) ^ e.rotatedRight(11) ^ e.rotatedRight(25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = a.rotatedRight(2) ^ a.rotatedRight(13) ^ a.rotatedRight(22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d
            h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
        }
        return h.flatMap { v in (0..<4).map { UInt8(truncatingIfNeeded: v >> UInt32(24 - $0 * 8)) } }
    }

    public static func hexDigest(_ message: [UInt8]) -> String {
        digest(message).map { hex($0) }.joined().lowercased()
    }
}

extension UInt32 {
    @inline(__always)
    func rotatedRight(_ n: UInt32) -> UInt32 { (self >> n) | (self << (32 - n)) }
}
