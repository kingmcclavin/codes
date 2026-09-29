/// Z80 flag bits (register F).
public enum Flag {
    public static let c: UInt8 = 0x01   // carry
    public static let n: UInt8 = 0x02   // add/subtract
    public static let pv: UInt8 = 0x04  // parity/overflow
    public static let x: UInt8 = 0x08   // undocumented copy of bit 3
    public static let h: UInt8 = 0x10   // half carry
    public static let y: UInt8 = 0x20   // undocumented copy of bit 5
    public static let z: UInt8 = 0x40   // zero
    public static let s: UInt8 = 0x80   // sign
    public static let xy: UInt8 = x | y
}

/// The complete Z80 programmer-visible register file, plus the internal
/// MEMPTR (WZ) register whose value leaks into the undocumented X/Y flags.
public struct Registers: Equatable, Codable, Sendable {
    public var a: UInt8 = 0xFF, f: UInt8 = 0xFF
    public var b: UInt8 = 0xFF, c: UInt8 = 0xFF
    public var d: UInt8 = 0xFF, e: UInt8 = 0xFF
    public var h: UInt8 = 0xFF, l: UInt8 = 0xFF

    public var altAF: UInt16 = 0xFFFF
    public var altBC: UInt16 = 0xFFFF
    public var altDE: UInt16 = 0xFFFF
    public var altHL: UInt16 = 0xFFFF

    public var ix: UInt16 = 0xFFFF
    public var iy: UInt16 = 0xFFFF
    public var sp: UInt16 = 0xFFFF
    public var pc: UInt16 = 0x0000
    public var i: UInt8 = 0x00
    public var r: UInt8 = 0x00
    public var wz: UInt16 = 0x0000

    public init() {}

    public var af: UInt16 {
        get { UInt16(a) << 8 | UInt16(f) }
        set { a = UInt8(truncatingIfNeeded: newValue >> 8); f = UInt8(truncatingIfNeeded: newValue) }
    }
    public var bc: UInt16 {
        get { UInt16(b) << 8 | UInt16(c) }
        set { b = UInt8(truncatingIfNeeded: newValue >> 8); c = UInt8(truncatingIfNeeded: newValue) }
    }
    public var de: UInt16 {
        get { UInt16(d) << 8 | UInt16(e) }
        set { d = UInt8(truncatingIfNeeded: newValue >> 8); e = UInt8(truncatingIfNeeded: newValue) }
    }
    public var hl: UInt16 {
        get { UInt16(h) << 8 | UInt16(l) }
        set { h = UInt8(truncatingIfNeeded: newValue >> 8); l = UInt8(truncatingIfNeeded: newValue) }
    }

    public func flag(_ mask: UInt8) -> Bool { f & mask != 0 }

    /// "SZ5H3PNC"-style rendering, lowercase for cleared flags.
    public var flagString: String {
        let names: [(UInt8, Character)] = [
            (Flag.s, "S"), (Flag.z, "Z"), (Flag.y, "5"), (Flag.h, "H"),
            (Flag.x, "3"), (Flag.pv, "P"), (Flag.n, "N"), (Flag.c, "C"),
        ]
        return String(names.map { f & $0.0 != 0 ? $0.1 : Character($0.1.lowercased()) })
    }
}
