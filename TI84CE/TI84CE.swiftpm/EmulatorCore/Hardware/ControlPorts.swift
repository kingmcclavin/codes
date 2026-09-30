import Foundation

/// System control ports (port range 0xxx): power, CPU speed, battery measurement,
/// device type, memory protection boundaries.
public final class ControlPorts: IODevice {
    public var ports = [UInt8](repeating: 0, count: 0x100)

    /// Battery level presented to the ROM (0 = empty ... 4 = full).
    public var batteryLevel: Int = 4

    /// Invoked when port 0x01 changes the CPU clock: 0 = 6 MHz, 1 = 12, 2 = 24, 3 = 48.
    var onCPUSpeedChange: ((UInt8) -> Void)?

    public var cpuSpeedIndex: UInt8 { ports[0x01] & 3 }

    public init() { reset() }

    public func reset() {
        ports = [UInt8](repeating: 0, count: 0x100)
    }

    /// Battery voltage comparator (port 0x02 bit 0).
    ///
    /// The ROM measures the battery by programming a reference threshold and
    /// reading the comparator: port 0x09 bits 5-4 select the presence check vs. the
    /// level ladder, and port 0x09 bit 7 together with port 0x00 bit 7 select one of
    /// four ascending thresholds. The comparator is high while the battery is above
    /// the selected threshold.
    var batteryComparator: Bool {
        let p9 = ports[0x09], p0 = ports[0x00]
        if p9 & 0x30 != 0 { return batteryLevel > 0 }       // battery-present check
        let rank: Int
        switch (p9 & 0x80 != 0, p0 & 0x80 != 0) {
        case (true, true): rank = 1
        case (true, false): rank = 2
        case (false, true): rank = 3
        case (false, false): rank = 4
        }
        return batteryLevel >= rank
    }

    public func read(_ offset: UInt16) -> UInt8 {
        let i = Int(offset & 0xFF)
        switch i {
        case 0x02:
            return (ports[i] & ~0x01) | (batteryComparator ? 0x01 : 0x00)
        case 0x03:
            return 0x00                       // device type: TI-84 Plus CE
        case 0x0B:
            return ports[i] & ~0x02           // not charging
        case 0x0F:
            return ports[i] & 0x03            // no USB cable / VBUS
        default:
            return ports[i]
        }
    }

    public func write(_ offset: UInt16, value: UInt8) {
        let i = Int(offset & 0xFF)
        switch i {
        case 0x01:
            ports[i] = value & 0x13
            onCPUSpeedChange?(value & 3)
        case 0x02:
            break                             // comparator output is read-only
        case 0x06:
            ports[i] = value & 0x07
        case 0x0D:
            // The written nibble is mirrored into the upper nibble (peripheral
            // enable handshake: writing 0x0F reads back 0xFF).
            ports[i] = (value & 0x0F) << 4 | (value & 0x0F)
        case 0x0F:
            ports[i] = value & 0x03
        case 0x3D:
            ports[i] = 0                      // protection status: write clears
        default:
            ports[i] = value
        }
    }

    public struct State: Codable, Equatable { var ports: [UInt8] }
    public var state: State {
        get { State(ports: ports) }
        set { ports = newValue.ports }
    }
}

/// Parallel-flash controller (port range 1xxx, memory-mapped at 0xE00000):
/// enables flash, sets the mapped size and the read wait states.
public final class FlashController: IODevice {
    public var ports = [UInt8](repeating: 0, count: 0x100)
    unowned(unsafe) let bus: MemoryBus

    init(bus: MemoryBus) {
        self.bus = bus
        reset()
    }

    public func reset() {
        ports = [UInt8](repeating: 0, count: 0x100)
        ports[0x00] = 0x01
        ports[0x02] = 0x06
        ports[0x05] = 0x04
        ports[0x07] = 0xFF
        applyWaitStates()
    }

    private func applyWaitStates() {
        bus.flashReadCycles = Int64(ports[0x05]) + 6
    }

    public func read(_ offset: UInt16) -> UInt8 { ports[Int(offset & 0xFF)] }

    public func write(_ offset: UInt16, value: UInt8) {
        let i = Int(offset & 0xFF)
        ports[i] = value
        if i == 0x05 { applyWaitStates() }
    }

    public var state: [UInt8] {
        get { ports }
        set { ports = newValue; applyWaitStates() }
    }
}
