import Foundation

/// A device that occupies part of the eZ80's 24-bit memory space.
/// Addresses passed in are offsets relative to the device's base.
public protocol MemoryDevice: AnyObject {
    func read(_ offset: UInt32) -> UInt8
    func write(_ offset: UInt32, value: UInt8)
}

/// A peripheral reachable through the eZ80 I/O space (IN/OUT, IN0/OUT0) and, on the
/// TI-84 Plus CE, also through memory-mapped windows at 0xE00000-0xFFFFFF.
/// `offset` is the register index within the peripheral's port range.
public protocol IODevice: AnyObject {
    func read(_ offset: UInt16) -> UInt8
    func write(_ offset: UInt16, value: UInt8)
    /// Side-effect free read for the debugger.
    func peek(_ offset: UInt16) -> UInt8
    func reset()
}

public extension IODevice {
    func peek(_ offset: UInt16) -> UInt8 { read(offset) }
}

/// Helpers for 32-bit little-endian registers exposed byte-wise.
@inline(__always) func byteOf(_ v: UInt32, _ index: Int) -> UInt8 {
    UInt8(truncatingIfNeeded: v >> (UInt32(index & 3) * 8))
}

@inline(__always) func setByte(_ v: inout UInt32, _ index: Int, _ b: UInt8) {
    let shift = UInt32(index & 3) * 8
    v = (v & ~(0xFF << shift)) | UInt32(b) << shift
}
