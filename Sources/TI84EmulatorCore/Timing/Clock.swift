/// Emulated time.
///
/// The CPU counts T-states, but the TI-84 Plus switches between 6 MHz and
/// 15 MHz while its timers keep running from fixed crystals. The clock
/// therefore keeps a master timebase in "ticks" of 1/30,000,000 s, where one
/// CPU cycle is exactly 5 ticks at 6 MHz and 2 ticks at 15 MHz, and converts
/// between the two whenever the CPU speed changes.
public final class EmulatorClock {
    public static let ticksPerSecond: UInt64 = 30_000_000
    public static let ticksPerMicrosecond: UInt64 = 30

    public enum Speed: UInt8, Codable, Sendable {
        case mhz6, mhz15
        public var cyclesPerSecond: UInt64 { self == .mhz6 ? 6_000_000 : 15_000_000 }
        public var ticksPerCycle: UInt64 { EmulatorClock.ticksPerSecond / cyclesPerSecond }
    }

    unowned let cpu: CPU
    public private(set) var speed: Speed = .mhz6
    private var baseTicks: UInt64 = 0
    private var baseCycles: UInt64 = 0

    init(cpu: CPU) {
        self.cpu = cpu
        baseCycles = cpu.cycles
    }

    /// Current emulated time in ticks.
    @inline(__always)
    public var now: UInt64 {
        baseTicks &+ (cpu.cycles &- baseCycles) &* speed.ticksPerCycle
    }

    public var ticksPerCycle: UInt64 { speed.ticksPerCycle }

    public func setSpeed(_ newSpeed: Speed) {
        guard newSpeed != speed else { return }
        baseTicks = now
        baseCycles = cpu.cycles
        speed = newSpeed
    }

    /// First CPU cycle count at which `now >= tick`.
    public func cycle(atTick tick: UInt64) -> UInt64 {
        let current = now
        if tick <= current { return cpu.cycles }
        let perCycle = speed.ticksPerCycle
        return cpu.cycles &+ (tick - current + perCycle - 1) / perCycle
    }

    public static func ticks(microseconds: Double) -> UInt64 {
        UInt64((microseconds * Double(ticksPerMicrosecond)).rounded())
    }

    var snapshot: ClockState {
        ClockState(speed: speed, now: now)
    }

    func restore(_ s: ClockState) {
        speed = s.speed
        baseTicks = s.now
        baseCycles = cpu.cycles
    }
}

public struct ClockState: Codable, Equatable, Sendable {
    var speed: EmulatorClock.Speed
    var now: UInt64
}

/// Deterministic event scheduler in master-clock ticks. Each hardware event
/// has a fixed slot; the emulator runs the CPU up to the earliest deadline,
/// then fires everything that is due.
public final class Scheduler {
    public enum Event: Int, CaseIterable, Codable, Sendable {
        case timer1, timer2a, timer2b
        case crystal1, crystal2, crystal3
        case lcdFrame
        case linkAssist
    }

    public static let never = UInt64.max

    private var deadlines = [UInt64](repeating: Scheduler.never, count: Event.allCases.count)
    private var handlers: [((UInt64) -> Void)?] = Array(repeating: nil, count: Event.allCases.count)
    public private(set) var nextDeadline: UInt64 = Scheduler.never

    unowned let clock: EmulatorClock

    init(clock: EmulatorClock) {
        self.clock = clock
    }

    /// Registers the callback for an event. The callback receives the tick
    /// the event was due at (so periodic events can reschedule without drift).
    func setHandler(_ event: Event, _ handler: @escaping (UInt64) -> Void) {
        handlers[event.rawValue] = handler
    }

    public func deadline(of event: Event) -> UInt64 { deadlines[event.rawValue] }

    public func isScheduled(_ event: Event) -> Bool { deadlines[event.rawValue] != Scheduler.never }

    public func schedule(_ event: Event, at tick: UInt64) {
        deadlines[event.rawValue] = tick
        if tick < nextDeadline {
            nextDeadline = tick
            // An event scheduled from inside CPU execution (via an OUT) may be
            // earlier than the CPU's current run target.
            clock.cpu.limitRun(toCycle: clock.cycle(atTick: tick))
        }
    }

    public func schedule(_ event: Event, after ticks: UInt64) {
        schedule(event, at: clock.now &+ ticks)
    }

    /// Re-derives the CPU run limit, e.g. after the CPU speed changed.
    func refreshRunLimit() {
        if nextDeadline != Scheduler.never {
            clock.cpu.limitRun(toCycle: clock.cycle(atTick: nextDeadline))
        }
    }

    public func cancel(_ event: Event) {
        deadlines[event.rawValue] = Scheduler.never
        recomputeNext()
    }

    /// Fires every event whose deadline has passed, in deadline order.
    func fireDue() {
        let now = clock.now
        while nextDeadline <= now {
            var index = 0
            for i in 1..<deadlines.count where deadlines[i] < deadlines[index] { index = i }
            let due = deadlines[index]
            deadlines[index] = Scheduler.never
            recomputeNext()
            handlers[index]?(due)
        }
    }

    private func recomputeNext() {
        nextDeadline = deadlines.min() ?? Scheduler.never
    }

    var snapshot: [UInt64] { deadlines }

    func restore(_ values: [UInt64]) {
        for i in 0..<min(values.count, deadlines.count) { deadlines[i] = values[i] }
        recomputeNext()
    }
}
