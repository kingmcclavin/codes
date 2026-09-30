import Foundation

/// eZ80 register file.
///
/// Multi-byte registers are stored as 24-bit values in `UInt32` (upper byte of the
/// storage is always zero). 16-bit register writes (Z80 mode or a .S suffix) clear
/// the upper byte (BCU/DEU/HLU/IXU/IYU); 8-bit writes leave it alone.
public struct Registers: Equatable, Codable {
    public var a: UInt8 = 0
    public var f: UInt8 = 0
    public var bc: UInt32 = 0
    public var de: UInt32 = 0
    public var hl: UInt32 = 0
    public var ix: UInt32 = 0
    public var iy: UInt32 = 0
    /// Z80-mode stack pointer (16-bit, combined with MBASE for addressing).
    public var sps: UInt32 = 0
    /// ADL-mode stack pointer (24-bit).
    public var spl: UInt32 = 0
    public var pc: UInt32 = 0
    /// Interrupt page register (16-bit on the eZ80).
    public var i: UInt16 = 0
    public var r: UInt8 = 0
    /// Z80-mode memory base: supplies address bits 23..16 when ADL = 0.
    public var mbase: UInt8 = 0

    // Shadow registers.
    public var a_: UInt8 = 0
    public var f_: UInt8 = 0
    public var bc_: UInt32 = 0
    public var de_: UInt32 = 0
    public var hl_: UInt32 = 0

    public init() {}

    @inline(__always) public var b: UInt8 {
        get { UInt8(truncatingIfNeeded: bc >> 8) }
        set { bc = (bc & 0xFF_00FF) | UInt32(newValue) << 8 }
    }
    @inline(__always) public var c: UInt8 {
        get { UInt8(truncatingIfNeeded: bc) }
        set { bc = (bc & 0xFF_FF00) | UInt32(newValue) }
    }
    @inline(__always) public var d: UInt8 {
        get { UInt8(truncatingIfNeeded: de >> 8) }
        set { de = (de & 0xFF_00FF) | UInt32(newValue) << 8 }
    }
    @inline(__always) public var e: UInt8 {
        get { UInt8(truncatingIfNeeded: de) }
        set { de = (de & 0xFF_FF00) | UInt32(newValue) }
    }
    @inline(__always) public var h: UInt8 {
        get { UInt8(truncatingIfNeeded: hl >> 8) }
        set { hl = (hl & 0xFF_00FF) | UInt32(newValue) << 8 }
    }
    @inline(__always) public var l: UInt8 {
        get { UInt8(truncatingIfNeeded: hl) }
        set { hl = (hl & 0xFF_FF00) | UInt32(newValue) }
    }
    @inline(__always) public var ixh: UInt8 {
        get { UInt8(truncatingIfNeeded: ix >> 8) }
        set { ix = (ix & 0xFF_00FF) | UInt32(newValue) << 8 }
    }
    @inline(__always) public var ixl: UInt8 {
        get { UInt8(truncatingIfNeeded: ix) }
        set { ix = (ix & 0xFF_FF00) | UInt32(newValue) }
    }
    @inline(__always) public var iyh: UInt8 {
        get { UInt8(truncatingIfNeeded: iy >> 8) }
        set { iy = (iy & 0xFF_00FF) | UInt32(newValue) << 8 }
    }
    @inline(__always) public var iyl: UInt8 {
        get { UInt8(truncatingIfNeeded: iy) }
        set { iy = (iy & 0xFF_FF00) | UInt32(newValue) }
    }
    @inline(__always) public var af: UInt16 {
        get { UInt16(a) << 8 | UInt16(f) }
        set { a = UInt8(newValue >> 8); f = UInt8(truncatingIfNeeded: newValue) }
    }
}

/// Flag bit masks for the F register.
public enum Flag {
    public static let c: UInt8 = 0x01
    public static let n: UInt8 = 0x02
    public static let pv: UInt8 = 0x04
    public static let x: UInt8 = 0x08
    public static let h: UInt8 = 0x10
    public static let y: UInt8 = 0x20
    public static let z: UInt8 = 0x40
    public static let s: UInt8 = 0x80

    public static func describe(_ f: UInt8) -> String {
        let names: [(UInt8, Character)] = [(s, "S"), (z, "Z"), (y, "5"), (h, "H"), (x, "3"), (pv, "P"), (n, "N"), (c, "C")]
        return String(names.map { f & $0.0 != 0 ? $0.1 : "-" })
    }
}
