import Foundation

/// Describes how the TI-84 Plus CE decodes the eZ80's 24-bit address space.
///
///     000000-3FFFFF  flash (4 MiB)
///     400000-CFFFFF  unmapped
///     D00000-D657FF  RAM (256 KiB) + VRAM (150 KiB); mirrored every 512 KiB up to DFFFFF
///     E00000-E3FFFF  memory-mapped I/O: flash ctrl, SHA256, USB, LCD (ports 1xxx-4xxx)
///     E40000-EFFFFF  unmapped
///     F00000-FAFFFF  memory-mapped I/O: interrupts .. fxxx (ports 5xxx-Fxxx)
///     FB0000-FFFFFF  unmapped
///
/// All decoding decisions live here so neither the CPU nor the devices need to know
/// about the layout.
public struct MemoryMapper {
    public enum Region: Equatable {
        case flash(offset: UInt32)
        case ram(offset: UInt32)
        case io(port: UInt16)
        case unmapped
    }

    public var flashSize: UInt32 = 0x400000
    public var ramBase: UInt32 = 0xD00000
    public var ramWindow: UInt32 = 0x80000     // 512 KiB mirror period
    public var ramSize: UInt32 = UInt32(RAM.size)

    public init() {}

    @inline(__always) public func decode(_ address: UInt32) -> Region {
        let a = address & 0xFF_FFFF
        if a < flashSize { return .flash(offset: a) }
        if a >= ramBase && a < 0xE00000 {
            let o = (a - ramBase) & (ramWindow - 1)
            return o < ramSize ? .ram(offset: o) : .unmapped
        }
        if let port = MemoryMapper.mmioPort(a) { return .io(port: port) }
        return .unmapped
    }

    /// Converts a memory-mapped I/O address to its equivalent I/O port.
    @inline(__always) public static func mmioPort(_ a: UInt32) -> UInt16? {
        let block = a >> 16
        let low = UInt16(a & 0xFFF)
        switch block {
        case 0xE0...0xE3: return UInt16(block - 0xE0 + 0x1) << 12 | low
        case 0xF0...0xFA: return UInt16(block - 0xF0 + 0x5) << 12 | low
        default: return nil
        }
    }
}
