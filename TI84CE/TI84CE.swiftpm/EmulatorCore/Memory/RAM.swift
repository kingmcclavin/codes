import Foundation

/// The CE's 256 KiB of user RAM plus 150 KiB of VRAM, one contiguous 0x65800-byte
/// block mapped at 0xD00000.
public final class RAM: MemoryDevice {
    public static let size = 0x65800

    /// Contiguous storage; exposed as a pointer so the bus and LCD can access it
    /// without per-access bounds checks or copy-on-write overhead.
    public let bytes: UnsafeMutablePointer<UInt8>

    public init() {
        bytes = .allocate(capacity: RAM.size)
        bytes.initialize(repeating: 0, count: RAM.size)
    }

    deinit { bytes.deallocate() }

    public func read(_ offset: UInt32) -> UInt8 {
        offset < RAM.size ? bytes[Int(offset)] : 0
    }

    public func write(_ offset: UInt32, value: UInt8) {
        if offset < RAM.size { bytes[Int(offset)] = value }
    }

    public func clear() { bytes.update(repeating: 0, count: RAM.size) }

    public var contents: [UInt8] {
        get { Array(UnsafeBufferPointer(start: bytes, count: RAM.size)) }
        set {
            let n = min(newValue.count, RAM.size)
            newValue.withUnsafeBufferPointer { bytes.update(from: $0.baseAddress!, count: n) }
        }
    }
}
