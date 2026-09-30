import Foundation

/// 4 MiB parallel NOR flash chip of the TI-84 Plus CE (pre-revision-M hardware).
///
/// The CPU cannot write flash directly: stores are interpreted as JEDEC/AMD-style
/// command sequences (unlock cycles at 0xAAA/0x555 in byte mode), exactly like the
/// real chip. This is how the OS programs the archive. Programming can only clear
/// bits; erasing sets a whole sector back to 0xFF. Operations complete instantly, so
/// both data#-polling and toggle-bit polling see "done" on the first status read.
public final class Flash: MemoryDevice {
    public static let size = ROMImage.flashSize
    /// Boot code sectors; the real hardware protects these, and so do we.
    public static let protectedEnd: UInt32 = 0x20000

    public let bytes: UnsafeMutablePointer<UInt8>

    public enum Mode: UInt8, Codable { case read, autoselect, cfi, eraseStatus }
    public private(set) var mode: Mode = .read {
        didSet {
            switch mode {
            case .read: readModeFlag.pointee = true
            default: readModeFlag.pointee = false
            }
        }
    }
    /// Mirrors `mode == .read` for the bus fast path.
    public let readModeFlag: UnsafeMutablePointer<Bool>
    private var step = 0
    private var programArmed = false
    /// Remaining reads that return the embedded-erase status byte instead of array
    /// data. The ROM's erase routine polls DQ3 (erase timer) and then DQ6 (toggle
    /// bit); a completed erase reports DQ7 = 1 with DQ6 steady and DQ3 = 0.
    private var eraseStatusReads = 0

    /// Called after the flash contents change (program / erase), for persistence.
    public var onModified: (() -> Void)?
    public private(set) var dirty = false

    public init() {
        bytes = .allocate(capacity: Flash.size)
        bytes.initialize(repeating: 0xFF, count: Flash.size)
        readModeFlag = .allocate(capacity: 1)
        readModeFlag.initialize(to: true)
    }

    deinit {
        bytes.deallocate()
        readModeFlag.deallocate()
    }

    public func load(_ image: [UInt8]) {
        let n = min(image.count, Flash.size)
        image.withUnsafeBufferPointer { bytes.update(from: $0.baseAddress!, count: n) }
        if n < Flash.size { (bytes + n).update(repeating: 0xFF, count: Flash.size - n) }
        resetCommandState()
        dirty = false
    }

    public var contents: [UInt8] { Array(UnsafeBufferPointer(start: bytes, count: Flash.size)) }

    public func markClean() { dirty = false }

    public func resetCommandState() {
        mode = .read; step = 0; programArmed = false; eraseStatusReads = 0
    }

    /// Fast path used by the bus when the chip is in array-read mode.
    @inline(__always) public var isReadMode: Bool { readModeFlag.pointee }

    public func read(_ offset: UInt32) -> UInt8 {
        let a = Int(offset) & (Flash.size - 1)
        switch mode {
        case .read:
            return bytes[a]
        case .autoselect:
            // Byte-mode autoselect: manufacturer at 0x00, device at 0x02,
            // sector protection status at 0x04 (unprotected).
            switch a & 0xFF {
            case 0x00: return 0xC2          // Macronix
            case 0x02: return 0xA8          // MX29LV320-class, bottom boot
            default: return 0x00
            }
        case .cfi:
            let cfi: [Int: UInt8] = [0x20: 0x51, 0x22: 0x52, 0x24: 0x59, 0x4E: 0x16]
            return cfi[a & 0xFF] ?? 0x00
        case .eraseStatus:
            eraseStatusReads -= 1
            if eraseStatusReads <= 0 { mode = .read }
            return 0x80
        }
    }

    public func write(_ offset: UInt32, value: UInt8) {
        let a = offset & UInt32(Flash.size - 1)
        let cmdAddr = a & 0xFFF

        if programArmed {
            programArmed = false
            step = 0
            program(a, value)
            return
        }
        if value == 0xF0 {             // reset / exit autoselect / exit CFI
            resetCommandState(); return
        }
        if value == 0x98 && (a & 0xFF) == 0xAA && step == 0 {
            mode = .cfi; return
        }
        switch step {
        case 0:
            step = (cmdAddr == 0xAAA && value == 0xAA) ? 1 : 0
        case 1:
            step = (cmdAddr == 0x555 && value == 0x55) ? 2 : 0
        case 2:
            step = 0
            guard cmdAddr == 0xAAA else { return }
            switch value {
            case 0xA0: programArmed = true
            case 0x80: step = 3
            case 0x90: mode = .autoselect
            default: break
            }
        case 3:
            step = (cmdAddr == 0xAAA && value == 0xAA) ? 4 : 0
        case 4:
            step = (cmdAddr == 0x555 && value == 0x55) ? 5 : 0
        case 5:
            step = 0
            if value == 0x30 { eraseSector(containing: a) }
            else if value == 0x10 && cmdAddr == 0xAAA { eraseChip() }
        default:
            step = 0
        }
    }

    private func program(_ a: UInt32, _ value: UInt8) {
        guard a >= Flash.protectedEnd else { return }
        let old = bytes[Int(a)]
        let new = old & value           // NOR flash programming only clears bits
        if new != old { bytes[Int(a)] = new; modified() }
    }

    /// Sector geometry: 8 KiB boot sectors in the first 64 KiB, 64 KiB elsewhere.
    public static func sectorRange(containing a: UInt32) -> Range<Int> {
        let size = a < 0x10000 ? 0x2000 : 0x10000
        let start = Int(a) & ~(size - 1)
        return start..<(start + size)
    }

    private func eraseSector(containing a: UInt32) {
        guard a >= Flash.protectedEnd else { enterEraseStatus(); return }
        let r = Flash.sectorRange(containing: a)
        (bytes + r.lowerBound).update(repeating: 0xFF, count: r.count)
        enterEraseStatus()
        modified()
    }

    private func enterEraseStatus() {
        mode = .eraseStatus
        eraseStatusReads = 3
    }

    private func eraseChip() {
        let start = Int(Flash.protectedEnd)
        (bytes + start).update(repeating: 0xFF, count: Flash.size - start)
        enterEraseStatus()
        modified()
    }

    private func modified() {
        dirty = true
        onModified?()
    }
}
