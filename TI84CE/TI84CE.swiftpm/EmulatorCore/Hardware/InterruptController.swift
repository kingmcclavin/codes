import Foundation

/// Interrupt source bits of the TI-84 Plus CE interrupt controller.
public enum InterruptSource {
    public static let on: UInt32       = 1 << 0
    public static let timer1: UInt32   = 1 << 1
    public static let timer2: UInt32   = 1 << 2
    public static let timer3: UInt32   = 1 << 3
    public static let osTimer: UInt32  = 1 << 4
    public static let keypad: UInt32   = 1 << 10
    public static let lcd: UInt32      = 1 << 11
    public static let rtc: UInt32      = 1 << 12
    public static let usb: UInt32      = 1 << 13
    public static let power: UInt32    = 1 << 15
    public static let wake: UInt32     = 1 << 19

    public static let names: [Int: String] = [
        0: "ON", 1: "Timer1", 2: "Timer2", 3: "Timer3", 4: "OS timer", 10: "Keypad",
        11: "LCD", 12: "RTC", 13: "USB", 15: "Power", 19: "Wake",
    ]
}

/// Interrupt controller (port range 5xxx, memory-mapped at 0xF00000).
///
/// Two identical register banks (0x00 and 0x20):
///
///     +00 raw status (R)       +04 enable mask (R/W)   +08 acknowledge (W)
///     +0C latch mode (R/W)     +10 invert (R/W)        +14 masked status (R)
///
/// Sources marked "latched" stay pending until acknowledged; the others follow the
/// level of their source line. The CPU's IRQ line is the OR of all masked status bits.
public final class InterruptController: IODevice {
    public struct Bank: Codable, Equatable {
        public var status: UInt32 = 0
        public var enabled: UInt32 = 0
        public var latched: UInt32 = 0
        public var inverted: UInt32 = 0
    }

    public private(set) var banks = [Bank(), Bank()]
    /// Current level of every source line.
    public private(set) var raw: UInt32 = 0

    unowned(unsafe) let cpu: CPU

    init(cpu: CPU) { self.cpu = cpu }

    public func reset() {
        banks = [Bank(), Bank()]
        raw = 0
        updateCPU()
    }

    /// Drives a source line.
    public func set(_ source: UInt32, _ level: Bool) {
        if level { raw |= source } else { raw &= ~source }
        for i in 0..<2 {
            var b = banks[i]
            let active = (level ? source : 0) ^ (b.inverted & source)
            if active != 0 {
                b.status |= source
            } else {
                b.status &= ~source | b.latched
            }
            banks[i] = b
        }
        updateCPU()
    }

    /// A momentary pulse: latched sources stay pending, level sources return low.
    public func pulse(_ source: UInt32) {
        set(source, true)
        set(source, false)
    }

    private func updateCPU() {
        cpu.irq = (banks[0].status & banks[0].enabled) | (banks[1].status & banks[1].enabled) != 0
    }

    public var pending: UInt32 { (banks[0].status & banks[0].enabled) | (banks[1].status & banks[1].enabled) }

    public func read(_ offset: UInt16) -> UInt8 {
        let o = Int(offset)
        if o < 0x40 {
            let b = banks[(o >> 5) & 1]
            let v: UInt32
            switch (o >> 2) & 7 {
            case 0: v = b.status
            case 1: v = b.enabled
            case 3: v = b.latched
            case 4: v = b.inverted
            case 5: v = b.status & b.enabled
            default: v = 0
            }
            return byteOf(v, o)
        }
        switch o & ~3 {
        case 0x50: return byteOf(0x0001_0900, o)   // revision
        case 0x54: return byteOf(0x0000_0016, o)   // number of sources
        default: return 0
        }
    }

    public func write(_ offset: UInt16, value: UInt8) {
        let o = Int(offset)
        guard o < 0x40 else { return }
        let bi = (o >> 5) & 1
        var b = banks[bi]
        switch (o >> 2) & 7 {
        case 1: setByte(&b.enabled, o, value)
        case 2:
            // Acknowledge clears latched sources; level sources follow their line.
            let ack = UInt32(value) << (UInt32(o & 3) * 8)
            b.status &= ~(ack & b.latched)
        case 3:
            setByte(&b.latched, o, value)
            b.status = (b.status & b.latched) | ((raw ^ b.inverted) & ~b.latched)
        case 4:
            setByte(&b.inverted, o, value)
            b.status = (b.status & b.latched) | ((raw ^ b.inverted) & ~b.latched)
        default: break
        }
        banks[bi] = b
        updateCPU()
    }

    public struct State: Codable, Equatable {
        var banks: [Bank]
        var raw: UInt32
    }

    public var state: State {
        get { State(banks: banks, raw: raw) }
        set { banks = newValue.banks; raw = newValue.raw; updateCPU() }
    }
}
