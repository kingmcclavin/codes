/// Interrupt sources on the TI-84 Plus ASIC. The raw values match the bit
/// positions reported by port 04h.
public struct InterruptSource: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let onKey = InterruptSource(rawValue: 0x01)
    public static let timer1 = InterruptSource(rawValue: 0x02)
    public static let timer2 = InterruptSource(rawValue: 0x04)
    public static let linkActivity = InterruptSource(rawValue: 0x10)
    public static let crystal1 = InterruptSource(rawValue: 0x20)
    public static let crystal2 = InterruptSource(rawValue: 0x40)
    public static let crystal3 = InterruptSource(rawValue: 0x80)
    /// Link assist read/idle/error (reported through port 09h, not 04h).
    public static let linkAssist = InterruptSource(rawValue: 0x100)

    public static let crystalTimers: InterruptSource = [.crystal1, .crystal2, .crystal3]
}

/// Collects interrupt requests from the peripherals and drives the Z80's
/// (level-triggered) /INT line. Everything is wired to the single maskable
/// interrupt; the OS runs in IM 1 and reads port 04h to find the source.
///
/// Port 03h is the enable mask:
///   bit 0 ON key, bit 1 hardware timer 1, bit 2 hardware timer 2,
///   bit 3 "stay powered during HALT", bit 4 link activity.
/// Clearing an enable bit also acknowledges that source. Port 02h writes
/// acknowledge without disabling (84+ ASIC).
public final class InterruptController {
    unowned let cpu: CPU

    public private(set) var pending: InterruptSource = []
    public private(set) var enableMask: UInt8 = 0x0B

    init(cpu: CPU) {
        self.cpu = cpu
    }

    public func reset() {
        pending = []
        enableMask = 0x0B
        update()
    }

    public var onKeyEnabled: Bool { enableMask & 0x01 != 0 }
    public var timer1Enabled: Bool { enableMask & 0x02 != 0 }
    public var timer2Enabled: Bool { enableMask & 0x04 != 0 }
    public var linkEnabled: Bool { enableMask & 0x10 != 0 }
    /// Port 03h bit 3: when clear, HALT puts the calculator in low-power mode.
    public var staysPoweredDuringHalt: Bool { enableMask & 0x08 != 0 }

    public func raise(_ source: InterruptSource) {
        pending.formUnion(source)
        update()
    }

    public func acknowledge(_ source: InterruptSource) {
        pending.subtract(source)
        update()
    }

    /// Port 03h write.
    func writeEnableMask(_ value: UInt8) {
        enableMask = value
        var cleared: InterruptSource = []
        if value & 0x01 == 0 { cleared.insert(.onKey) }
        if value & 0x02 == 0 { cleared.insert(.timer1) }
        if value & 0x04 == 0 { cleared.insert(.timer2) }
        if value & 0x10 == 0 { cleared.insert(.linkActivity) }
        acknowledge(cleared)
    }

    /// Port 02h write (acknowledge).
    func writeAcknowledge(_ value: UInt8) {
        var cleared: InterruptSource = []
        if value & 0x01 == 0 { cleared.insert(.onKey) }
        if value & 0x02 == 0 { cleared.insert(.timer1) }
        if value & 0x04 == 0 { cleared.insert(.timer2) }
        if value & 0x10 == 0 { cleared.insert(.linkActivity) }
        acknowledge(cleared)
    }

    private func update() {
        cpu.irqLine = !pending.isEmpty
    }

    var snapshot: InterruptState { InterruptState(pending: pending.rawValue, enableMask: enableMask) }

    func restore(_ s: InterruptState) {
        pending = InterruptSource(rawValue: s.pending)
        enableMask = s.enableMask
        update()
    }
}

public struct InterruptState: Codable, Equatable, Sendable {
    var pending: UInt16
    var enableMask: UInt8
}
