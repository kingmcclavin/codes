import Foundation

/// The eZ80 16-bit I/O space as wired on the TI-84 Plus CE.
///
/// Bits 15..12 of the port address select one of 16 peripherals; the remaining bits
/// (masked to each peripheral's decoded width, so smaller devices are mirrored)
/// select a register.
public final class IOBus {
    public static let deviceNames = [
        "Control", "Flash ctrl", "SHA256", "USB", "LCD", "Interrupts", "Watchdog", "Timers",
        "RTC", "Protected", "Keypad", "Backlight", "Cxxx", "SPI", "UART", "Fxxx",
    ]
    static let mirrorMasks: [UInt16] = [
        0x00FF, 0x00FF, 0x00FF, 0x0FFF, 0x0FFF, 0x00FF, 0x00FF, 0x007F,
        0x00FF, 0x00FF, 0x007F, 0x00FF, 0x00FF, 0x007F, 0x00FF, 0x00FF,
    ]

    private var devices: [IODevice]

    /// Optional trace hook for the debugger / headless tracer: (port, value, isWrite).
    public var trace: ((UInt16, UInt8, Bool) -> Void)?

    public init() {
        devices = (0..<16).map { _ in NullDevice() }
    }

    public func attach(_ device: IODevice, at index: Int) {
        devices[index] = device
    }

    public func device(at index: Int) -> IODevice { devices[index] }

    @inline(__always) public func read(_ port: UInt16) -> UInt8 {
        let d = Int(port >> 12)
        let v = devices[d].read(port & IOBus.mirrorMasks[d])
        trace?(port, v, false)
        return v
    }

    @inline(__always) public func write(_ port: UInt16, value: UInt8) {
        let d = Int(port >> 12)
        trace?(port, value, true)
        devices[d].write(port & IOBus.mirrorMasks[d], value: value)
    }

    public func peek(_ port: UInt16) -> UInt8 {
        let d = Int(port >> 12)
        return devices[d].peek(port & IOBus.mirrorMasks[d])
    }

    public func resetAll() { devices.forEach { $0.reset() } }
}

/// Placeholder for unpopulated port ranges: reads 0, ignores writes.
final class NullDevice: IODevice {
    func read(_ offset: UInt16) -> UInt8 { 0 }
    func write(_ offset: UInt16, value: UInt8) {}
    func reset() {}
}

/// A peripheral we model only as a bank of read/write registers. Used for blocks the
/// OS configures but whose behaviour does not influence execution (UART, Cxxx, ...).
public final class RegisterFileDevice: IODevice {
    public var regs: [UInt8]
    private let defaults: [Int: UInt8]
    private let readOnly: Set<Int>

    public init(size: Int, defaults: [Int: UInt8] = [:], readOnly: Set<Int> = []) {
        regs = [UInt8](repeating: 0, count: size)
        self.defaults = defaults
        self.readOnly = readOnly
        reset()
    }

    public func read(_ offset: UInt16) -> UInt8 { regs[Int(offset) % regs.count] }
    public func write(_ offset: UInt16, value: UInt8) {
        let i = Int(offset) % regs.count
        if !readOnly.contains(i) { regs[i] = value }
    }
    public func reset() {
        for i in regs.indices { regs[i] = 0 }
        for (k, v) in defaults { regs[k] = v }
    }
}
