/// The two fixed-rate "hardware timer" interrupts the OS uses for its
/// periodic housekeeping (keyboard scan, cursor blink, APD).
///
/// On the TI-84 Plus they are derived from the 32 kHz crystal, independent of
/// CPU speed. Port 04h bits 1–2 select the period; timer 2 fires twice per
/// period, slightly before timer 1.
public final class HardwareTimers {
    /// Periods in microseconds for port 04h bits 1–2 = 0...3.
    public static let periods: [Double] = [1953, 4395, 6836, 9277]

    unowned let scheduler: Scheduler
    unowned let interrupts: InterruptController
    public private(set) var periodIndex = 3

    init(scheduler: Scheduler, interrupts: InterruptController) {
        self.scheduler = scheduler
        self.interrupts = interrupts
        scheduler.setHandler(.timer1) { [unowned self] due in fire(.timer1, due) }
        scheduler.setHandler(.timer2a) { [unowned self] due in fire(.timer2a, due) }
        scheduler.setHandler(.timer2b) { [unowned self] due in fire(.timer2b, due) }
    }

    public var period: UInt64 { EmulatorClock.ticks(microseconds: Self.periods[periodIndex]) }
    public var frequency: Double { 1_000_000 / Self.periods[periodIndex] }

    func reset() {
        periodIndex = 3
        scheduler.schedule(.timer1, after: EmulatorClock.ticks(microseconds: 1600))
        scheduler.schedule(.timer2a, after: EmulatorClock.ticks(microseconds: 1300))
        scheduler.schedule(.timer2b, after: EmulatorClock.ticks(microseconds: 1000))
    }

    /// Port 04h write; the new period applies from the next expiry.
    func setFrequency(fromPort04 value: UInt8) {
        periodIndex = Int((value >> 1) & 0x03)
    }

    private func fire(_ event: Scheduler.Event, _ due: UInt64) {
        switch event {
        case .timer1:
            if interrupts.timer1Enabled { interrupts.raise(.timer1) }
        default:
            if interrupts.timer2Enabled { interrupts.raise(.timer2) }
        }
        scheduler.schedule(event, at: due &+ period)
    }

    var snapshot: Int { periodIndex }
    func restore(_ index: Int) { periodIndex = index & 3 }
}

/// The three programmable "crystal" timers of the TI-84 Plus (ports 30h–38h).
///
/// Each timer has a frequency port (30h/33h/36h), a mode/status port
/// (31h/34h/37h) and a counter port (32h/35h/38h). Writing the counter starts
/// a countdown; expiry sets a status bit visible in port 04h bits 5–7 and can
/// raise an interrupt.
public final class CrystalTimers: IODevice {
    public struct Timer: Codable, Equatable, Sendable {
        public var frequency: UInt8 = 0
        public var loopValue: UInt8 = 0
        public var loop = false
        public var interruptEnabled = false
        public var overflow = false
        public var finished = false
        public var suppressHaltInterrupt = false
        public var running = false
        /// Tick at which the timer was (re)loaded for the current countdown.
        public var startTick: UInt64 = 0
        /// Repeat period in ticks after the current expiry (0 = stop).
        public var repeatPeriod: UInt64 = 0

        var statusByte: UInt8 {
            (loop ? 1 : 0) | (interruptEnabled ? 2 : 0) | (overflow ? 4 : 0)
        }
    }

    /// Microseconds per tick, times 32768, for frequency settings 40h–47h.
    private static let microsTimes32768: [UInt64] = [3_000_000, 33_000_000, 328_000_000, 3_277_000_000,
                                                     1_000_000, 16_000_000, 256_000_000, 4_096_000_000]
    private static let events: [Scheduler.Event] = [.crystal1, .crystal2, .crystal3]
    private static let sources: [InterruptSource] = [.crystal1, .crystal2, .crystal3]

    public private(set) var timers = [Timer](repeating: Timer(), count: 3)

    unowned let clock: EmulatorClock
    unowned let scheduler: Scheduler
    unowned let interrupts: InterruptController

    init(clock: EmulatorClock, scheduler: Scheduler, interrupts: InterruptController) {
        self.clock = clock
        self.scheduler = scheduler
        self.interrupts = interrupts
        for n in 0..<3 {
            scheduler.setHandler(Self.events[n]) { [unowned self] due in expired(n, due) }
        }
    }

    func reset() {
        timers = [Timer](repeating: Timer(), count: 3)
        for event in Self.events { scheduler.cancel(event) }
    }

    /// Port 04h bits 5–7.
    public var finishedBits: UInt8 {
        (timers[0].finished ? 0x20 : 0) | (timers[1].finished ? 0x40 : 0) | (timers[2].finished ? 0x80 : 0)
    }

    /// Port 03h write: timer interrupts are suppressed while halted unless
    /// one of the hardware timer interrupts is enabled.
    func setHaltSuppression(fromPort03 value: UInt8) {
        let suppress = value & 0x06 == 0
        for n in 0..<3 { timers[n].suppressHaltInterrupt = suppress }
    }

    // MARK: IODevice

    public func read(port: UInt8) -> UInt8 {
        let n = Int(port &- 0x30) / 3
        guard n < 3 else { return 0 }
        switch Int(port &- 0x30) % 3 {
        case 0: return timers[n].frequency
        case 1: return timers[n].statusByte
        default: return counterValue(n)
        }
    }

    public func write(port: UInt8, value: UInt8) {
        let n = Int(port &- 0x30) / 3
        guard n < 3 else { return }
        switch Int(port &- 0x30) % 3 {
        case 0: setFrequency(n, value)
        case 1: setMode(n, value)
        default: start(n, value)
        }
    }

    // MARK: Behaviour

    /// Length in ticks of `count` timer ticks at the timer's frequency, or 0
    /// when the frequency setting disables the timer.
    private func duration(_ n: Int, ticks count: UInt64) -> UInt64 {
        let f = timers[n].frequency
        if f & 0x80 != 0 {
            // CPU clock divided by 1, 2, 4, ... 64.
            var divider: UInt64 = 1
            for bit in (0...5).reversed() where f & (1 << bit) != 0 {
                divider = 2 << UInt64(bit)
                break
            }
            return count * divider * clock.ticksPerCycle
        }
        if f & 0x40 != 0 {
            // 32768 Hz crystal divided down: 10922, 993, 99.9, 10 Hz; 32768, 2048, 128, 8 Hz.
            let micros = (Self.microsTimes32768[Int(f & 7)] * count + 16384) / 32768
            return micros * EmulatorClock.ticksPerMicrosecond
        }
        return 0
    }

    private func normalDuration(_ n: Int) -> UInt64 {
        duration(n, ticks: timers[n].loopValue == 0 ? 256 : UInt64(timers[n].loopValue))
    }

    private func overflowDuration(_ n: Int) -> UInt64 {
        duration(n, ticks: 256)
    }

    private func counterValue(_ n: Int) -> UInt8 {
        let t = timers[n]
        guard t.running else { return t.loopValue }
        let full = overflowDuration(n)
        guard full > 0 else { return t.loopValue }
        let deadline = scheduler.deadline(of: Self.events[n])
        let now = clock.now
        let remaining = deadline > now ? deadline - now : 0
        return UInt8(truncatingIfNeeded: (remaining * 256 / full) % 256)
    }

    private func setFrequency(_ n: Int, _ value: UInt8) {
        // Changing the frequency stops the timer, latching the current count.
        timers[n].loopValue = counterValue(n)
        stop(n)
        timers[n].frequency = value
    }

    private func setMode(_ n: Int, _ value: UInt8) {
        timers[n].loop = value & 1 != 0
        timers[n].interruptEnabled = value & 2 != 0
        timers[n].finished = false
        timers[n].overflow = false
        interrupts.acknowledge(Self.sources[n])
        timers[n].repeatPeriod = (timers[n].loop || timers[n].loopValue == 0) ? normalDuration(n) : 0
    }

    private func start(_ n: Int, _ value: UInt8) {
        timers[n].loopValue = value
        let count = normalDuration(n)
        guard count > 0 else { return }
        if value == 0 || timers[n].finished {
            timers[n].repeatPeriod = overflowDuration(n)
        } else if !timers[n].loop {
            timers[n].repeatPeriod = 0
        } else {
            timers[n].repeatPeriod = count
        }
        timers[n].running = true
        timers[n].startTick = clock.now
        scheduler.schedule(Self.events[n], after: count)
    }

    private func stop(_ n: Int) {
        timers[n].running = false
        scheduler.cancel(Self.events[n])
    }

    private func expired(_ n: Int, _ due: UInt64) {
        if timers[n].loopValue != 0 {
            if timers[n].finished { timers[n].overflow = true }
            timers[n].finished = true
            if timers[n].interruptEnabled && !(timers[n].suppressHaltInterrupt && clock.cpu.halted) {
                interrupts.raise(Self.sources[n])
            }
            if timers[n].loop { timers[n].repeatPeriod = overflowDuration(n) }
        }
        if timers[n].repeatPeriod > 0 {
            timers[n].startTick = due
            scheduler.schedule(Self.events[n], at: due &+ timers[n].repeatPeriod)
        } else {
            timers[n].running = false
        }
    }

    var snapshot: [Timer] { timers }
    func restore(_ state: [Timer]) { if state.count == 3 { timers = state } }
}
