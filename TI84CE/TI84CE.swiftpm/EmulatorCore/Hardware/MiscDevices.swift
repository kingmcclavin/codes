import Foundation

/// Watchdog timer (port range 6xxx, memory-mapped at 0xF10000). The OS configures it
/// but leaves it disabled in normal operation; we model its registers faithfully
/// and reset the machine only if the ROM enables the reset output and lets it expire.
public final class Watchdog: IODevice {
    public private(set) var load: UInt32 = 0x03EF_1480
    public private(set) var counter: UInt32 = 0x03EF_1480
    public private(set) var control: UInt8 = 0
    public private(set) var status: UInt8 = 0

    public init() {}

    public func reset() {
        load = 0x03EF_1480; counter = load; control = 0; status = 0
    }

    public func read(_ offset: UInt16) -> UInt8 {
        let o = Int(offset)
        switch o {
        case 0x00..<0x04: return byteOf(counter, o)
        case 0x04..<0x08: return byteOf(load, o)
        case 0x0C: return control
        case 0x10: return status
        case 0x1C..<0x20: return byteOf(0x0001_0602, o)
        default: return 0
        }
    }

    public func write(_ offset: UInt16, value: UInt8) {
        let o = Int(offset)
        switch o {
        case 0x04..<0x08: setByte(&load, o, value)
        case 0x08: if value == 0xB9 { counter = load }      // restart key 0x5AB9 (low byte)
        case 0x0C: control = value
        case 0x14: status = 0
        default: break
        }
    }

    public struct State: Codable, Equatable { var load, counter: UInt32; var control, status: UInt8 }
    public var state: State {
        get { State(load: load, counter: counter, control: control, status: status) }
        set { load = newValue.load; counter = newValue.counter; control = newValue.control; status = newValue.status }
    }
}

/// LCD backlight PWM (port range Bxxx, memory-mapped at 0xF60000).
/// Register 0x24 holds the brightness level (0 = brightest, 255 = darkest).
public final class Backlight: IODevice {
    public var regs = [UInt8](repeating: 0, count: 0x100)

    public init() { reset() }

    public func reset() {
        regs = [UInt8](repeating: 0, count: 0x100)
        regs[0x24] = 0x00
    }

    /// Brightness as a fraction 0...1 for the renderer.
    public var brightness: Double { 1.0 - Double(regs[0x24]) / 255.0 * 0.85 }

    public func read(_ offset: UInt16) -> UInt8 { regs[Int(offset & 0xFF)] }
    public func write(_ offset: UInt16, value: UInt8) { regs[Int(offset & 0xFF)] = value }
}

/// USB OTG controller (port range 3xxx, memory-mapped at 0xE20000) — the CE's link
/// port. We emulate the controller's register interface in the "no cable attached"
/// state: the OS sees a healthy, idle controller and never waits on a transfer.
public final class LinkPort: IODevice {
    public var regs = [UInt8](repeating: 0, count: 0x1000)

    public init() { reset() }

    public func reset() {
        regs = [UInt8](repeating: 0, count: 0x1000)
        // EHCI-style capability registers of the FOTG210 core.
        put32(0x00, 0x0100_0010)       // CAPLENGTH / HCIVERSION
        put32(0x04, 0x0000_0001)       // HCSPARAMS: one port
        put32(0x08, 0x0000_0006)       // HCCPARAMS
        put32(0x14, 0x0000_1000)       // USBSTS: host controller halted
        put32(0x80, 0x0021_0000)       // OTG control/status: ID = B-device, no session
    }

    private func put32(_ o: Int, _ v: UInt32) {
        for i in 0..<4 { regs[o + i] = byteOf(v, i) }
    }

    public var cableConnected: Bool { false }

    public func read(_ offset: UInt16) -> UInt8 { regs[Int(offset) & 0xFFF] }

    public func write(_ offset: UInt16, value: UInt8) {
        let o = Int(offset) & 0xFFF
        switch o {
        case 0x00..<0x10:
            break                      // capability registers are read-only
        case 0x14..<0x18, 0x84..<0x88, 0xC0..<0xC4, 0x140..<0x148:
            regs[o] &= ~value          // status registers: write 1 to clear
        default:
            regs[o] = value
        }
    }
}
