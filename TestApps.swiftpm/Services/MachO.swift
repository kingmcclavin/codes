import Foundation

/// Best-effort Mach-O architecture detection from the raw executable bytes.
/// We only read the header(s); we never load or execute anything.
enum MachO {
    // Magic numbers.
    private static let MH_MAGIC: UInt32    = 0xFEEDFACE   // 32-bit, same endian
    private static let MH_CIGAM: UInt32    = 0xCEFAEDFE   // 32-bit, swapped
    private static let MH_MAGIC_64: UInt32 = 0xFEEDFACF   // 64-bit, same endian
    private static let MH_CIGAM_64: UInt32 = 0xCFFAEDFE   // 64-bit, swapped
    private static let FAT_MAGIC: UInt32   = 0xCAFEBABE
    private static let FAT_CIGAM: UInt32   = 0xBEBAFECA

    // cpu types.
    private static let CPU_ARCH_ABI64: UInt32 = 0x0100_0000
    private static let CPU_TYPE_ARM: UInt32   = 12
    private static let CPU_TYPE_X86: UInt32   = 7

    static func architectures(in data: Data) -> [String] {
        guard data.count >= 8 else { return [] }
        let magic = beOrLe32(data, 0, bigEndian: true)   // read as-is both ways below
        let magicLE = le32(data, 0)

        if magicLE == FAT_MAGIC || magicLE == FAT_CIGAM
            || magic == FAT_MAGIC || magic == FAT_CIGAM {
            return fatArchitectures(data)
        }
        if let arch = thinArchitecture(data, at: 0) {
            return [arch]
        }
        return []
    }

    private static func fatArchitectures(_ data: Data) -> [String] {
        // fat_header: magic(4, big-endian) nfat_arch(4, big-endian)
        guard data.count >= 8 else { return [] }
        let nfat = be32(data, 4)
        var result: [String] = []
        var off = 8
        for _ in 0..<min(nfat, 16) {
            guard off + 20 <= data.count else { break }
            let cputype = be32(data, off)        // fat_arch.cputype
            let offset = Int(be32(data, off + 8)) // fat_arch.offset
            if let name = archName(cpuType: cputype) {
                result.append(name)
            } else if offset + 4 <= data.count, let a = thinArchitecture(data, at: offset) {
                result.append(a)
            }
            off += 20
        }
        return result
    }

    private static func thinArchitecture(_ data: Data, at off: Int) -> String? {
        guard off + 8 <= data.count else { return nil }
        let magicLE = le32(data, off)
        let magicBE = be32(data, off)
        let is64: Bool
        let bigEndian: Bool
        switch true {
        case magicLE == MH_MAGIC_64: is64 = true;  bigEndian = false
        case magicLE == MH_CIGAM_64: is64 = true;  bigEndian = true
        case magicLE == MH_MAGIC:    is64 = false; bigEndian = false
        case magicLE == MH_CIGAM:    is64 = false; bigEndian = true
        case magicBE == MH_MAGIC_64: is64 = true;  bigEndian = true
        case magicBE == MH_MAGIC:    is64 = false; bigEndian = true
        default: return nil
        }
        _ = is64
        let cputype = bigEndian ? be32(data, off + 4) : le32(data, off + 4)
        return archName(cpuType: cputype)
    }

    private static func archName(cpuType: UInt32) -> String? {
        if cpuType == (CPU_TYPE_ARM | CPU_ARCH_ABI64) { return "arm64" }
        if cpuType == CPU_TYPE_ARM { return "armv7" }
        if cpuType == (CPU_TYPE_X86 | CPU_ARCH_ABI64) { return "x86_64" }
        if cpuType == CPU_TYPE_X86 { return "i386" }
        return nil
    }

    // MARK: byte readers
    private static func le32(_ d: Data, _ o: Int) -> UInt32 {
        UInt32(d[o]) | (UInt32(d[o+1]) << 8) | (UInt32(d[o+2]) << 16) | (UInt32(d[o+3]) << 24)
    }
    private static func be32(_ d: Data, _ o: Int) -> UInt32 {
        (UInt32(d[o]) << 24) | (UInt32(d[o+1]) << 16) | (UInt32(d[o+2]) << 8) | UInt32(d[o+3])
    }
    private static func beOrLe32(_ d: Data, _ o: Int, bigEndian: Bool) -> UInt32 {
        bigEndian ? be32(d, o) : le32(d, o)
    }
}
