import Foundation

/// The three 32-bit general purpose timers (port range 7xxx, memory-mapped at 0xF20000).
///
///     +00/+10/+20  counter     +04/+14/+24  reload value
///     +08/+18/+28  match 1     +0C/+1C/+2C  match 2
///     +30 control: per timer n, bit 3n enable, 3n+1 clock (0 = CPU, 1 = 32768 Hz),
///                  3n+2 overflow interrupt enable; bit 9+n counts up
///     +34 status (write 1 to clear): per timer n, bit 3n match1, 3n+1 match2, 3n+2 overflow
///     +38 interrupt mask (1 = masked)   +3C revision
///
/// Counters are evaluated lazily: whenever a register is touched or a scheduled
/// event fires, the elapsed emulated time is converted into counts. The next match
/// or overflow is scheduled exactly, so interrupt timing is deterministic.
/// Every match/overflow event pulses the timer's interrupt line (the interrupt
/// controller latches it), independent of whether software cleared the status bits.
public final class GeneralPurposeTimers: IODevice {
    public struct Channel: Codable, Equatable {
        public var counter: UInt32 = 0
        public var reload: UInt32 = 0
        public var match1: UInt32 = 0
        public var match2: UInt32 = 0
        /// Base ticks accumulated toward the next count.
        var residue: UInt64 = 0
    }

    public private(set) var channels = [Channel(), Channel(), Channel()]
    public private(set) var control: UInt32 = 0
    public private(set) var status: UInt32 = 0
    public private(set) var mask: UInt32 = 0
    private var lastSync: UInt64 = 0
    /// Status bits newly raised since the last interrupt update.
    private var fired: UInt32 = 0

    unowned let scheduler: Scheduler
    unowned let interrupts: InterruptController

    init(scheduler: Scheduler, interrupts: InterruptController) {
        self.scheduler = scheduler
        self.interrupts = interrupts
    }

    public func reset() {
        channels = [Channel(), Channel(), Channel()]
        control = 0; status = 0; mask = 0
        lastSync = scheduler.now
        scheduler.cancel(.gpt)
        updateInterrupts()
    }

    @inline(__always) private func enabled(_ n: Int) -> Bool { control & (1 << (3 * n)) != 0 }
    @inline(__always) private func uses32k(_ n: Int) -> Bool { control & (2 << (3 * n)) != 0 }
    @inline(__always) private func overflowEnabled(_ n: Int) -> Bool { control & (4 << (3 * n)) != 0 }
    @inline(__always) private func countsUp(_ n: Int) -> Bool { control & (1 << (9 + n)) != 0 }

    private func ticksPerCount(_ n: Int) -> UInt64 {
        uses32k(n) ? Scheduler.ticksPer32k : scheduler.ticksPerCycle
    }

    /// Brings all counters up to the current emulated time.
    public func sync() {
        let now = scheduler.now
        let elapsed = now &- lastSync
        lastSync = now
        guard elapsed > 0 else { return }
        for n in 0..<3 where enabled(n) {
            let tpc = ticksPerCount(n)
            let total = channels[n].residue + elapsed
            channels[n].residue = total % tpc
            advance(n, by: total / tpc)
        }
    }

    /// Advances channel `n` by `steps` counts, recording matches and overflows.
    private func advance(_ n: Int, by steps: UInt64) {
        guard steps > 0 else { return }
        var ch = channels[n]
        var remaining = steps
        let up = countsUp(n)
        let base = UInt32(3 * n)
        // Counts until wrap: counting down, the step taken at 0 overflows and reloads;
        // counting up, the step taken at 0xFFFFFFFF does.
        while remaining > 0 {
            let toBoundary: UInt64 = up ? UInt64(0xFFFF_FFFF - ch.counter) : UInt64(ch.counter)
            if remaining <= toBoundary {
                let from = ch.counter
                ch.counter = up ? ch.counter &+ UInt32(remaining) : ch.counter &- UInt32(remaining)
                checkMatches(&ch, from: from, to: ch.counter, up: up, base: base)
                remaining = 0
            } else {
                let from = ch.counter
                let edge: UInt32 = up ? 0xFFFF_FFFF : 0
                checkMatches(&ch, from: from, to: edge, up: up, base: base)
                remaining -= toBoundary + 1
                if overflowEnabled(n) { status |= 4 << base; fired |= 4 << base }
                ch.counter = ch.reload
                if ch.counter == ch.match1 { status |= 1 << base; fired |= 1 << base }
                if ch.counter == ch.match2 { status |= 2 << base; fired |= 2 << base }
                // Skip whole reload periods at once (their matches are already recorded).
                let period: UInt64 = up ? UInt64(0xFFFF_FFFF - ch.reload) + 1 : UInt64(ch.reload) + 1
                if remaining > period {
                    checkMatches(&ch, from: ch.counter, to: edge, up: up, base: base)
                    remaining %= period
                }
            }
        }
        channels[n] = ch
    }

    /// Records match flags for values strictly after `from` up to and including `to`.
    private func checkMatches(_ ch: inout Channel, from: UInt32, to: UInt32, up: Bool, base: UInt32) {
        func hit(_ m: UInt32) -> Bool { up ? (m > from && m <= to) : (m < from && m >= to) }
        if hit(ch.match1) { status |= 1 << base; fired |= 1 << base }
        if hit(ch.match2) { status |= 2 << base; fired |= 2 << base }
    }

    /// Number of counts until channel `n` next sets a status bit, if ever.
    private func countsToNextEvent(_ n: Int) -> UInt64? {
        let ch = channels[n]
        let up = countsUp(n)
        var best: UInt64?
        func consider(_ c: UInt64) { if c > 0 { best = min(best ?? c, c) } }
        let toBoundary: UInt64 = up ? UInt64(0xFFFF_FFFF - ch.counter) + 1 : UInt64(ch.counter) + 1
        consider(toBoundary)
        for m in [ch.match1, ch.match2] {
            if up, m > ch.counter { consider(UInt64(m - ch.counter)) }
            if !up, m < ch.counter { consider(UInt64(ch.counter - m)) }
        }
        return best
    }

    /// Schedules the next time an unmasked timer interrupt could fire.
    func scheduleNext() {
        var next: UInt64 = .max
        for n in 0..<3 where enabled(n) && (~mask >> (3 * n)) & 7 != 0 {
            guard let counts = countsToNextEvent(n) else { continue }
            let tpc = ticksPerCount(n)
            let ticks = counts * tpc - min(channels[n].residue, counts * tpc - 1)
            next = min(next, lastSync &+ ticks)
        }
        if next == .max { scheduler.cancel(.gpt) } else { scheduler.schedule(.gpt, at: next) }
    }

    /// Pulses the interrupt line of every timer that raised an unmasked event.
    func updateInterrupts() {
        let events = fired & ~mask
        fired = 0
        guard events != 0 else { return }
        for n in 0..<3 where (events >> (3 * n)) & 7 != 0 {
            interrupts.pulse(InterruptSource.timer1 << UInt32(n))
        }
    }

    /// Scheduler callback.
    func handleEvent() {
        sync()
        updateInterrupts()
        scheduleNext()
    }

    /// Must be called before the CPU clock changes (CPU-clocked channels).
    func willChangeCPUClock() { sync() }
    func didChangeCPUClock() { scheduleNext() }

    public func read(_ offset: UInt16) -> UInt8 {
        sync()
        return peek(offset)
    }

    public func peek(_ offset: UInt16) -> UInt8 {
        let o = Int(offset)
        switch o {
        case 0x00..<0x30:
            let ch = channels[o >> 4]
            switch (o >> 2) & 3 {
            case 0: return byteOf(ch.counter, o)
            case 1: return byteOf(ch.reload, o)
            case 2: return byteOf(ch.match1, o)
            default: return byteOf(ch.match2, o)
            }
        case 0x30..<0x34: return byteOf(control, o)
        case 0x34..<0x38: return byteOf(status, o)
        case 0x38..<0x3C: return byteOf(mask, o)
        case 0x3C..<0x40: return byteOf(0x0001_0801, o)
        default: return 0
        }
    }

    public func write(_ offset: UInt16, value: UInt8) {
        sync()
        let o = Int(offset)
        switch o {
        case 0x00..<0x30:
            let n = o >> 4
            switch (o >> 2) & 3 {
            case 0: setByte(&channels[n].counter, o, value)
            case 1: setByte(&channels[n].reload, o, value)
            case 2: setByte(&channels[n].match1, o, value)
            default: setByte(&channels[n].match2, o, value)
            }
        case 0x30..<0x34:
            setByte(&control, o, value)
        case 0x34..<0x38:
            status &= ~(UInt32(value) << (UInt32(o & 3) * 8))
        case 0x38..<0x3C:
            setByte(&mask, o, value)
        default:
            break
        }
        updateInterrupts()
        scheduleNext()
    }

    public struct State: Codable, Equatable {
        var channels: [Channel]
        var control, status, mask: UInt32
        var lastSync: UInt64
    }

    public var state: State {
        get { State(channels: channels, control: control, status: status, mask: mask, lastSync: lastSync) }
        set {
            channels = newValue.channels; control = newValue.control; status = newValue.status
            mask = newValue.mask; lastSync = newValue.lastSync
            updateInterrupts()
        }
    }
}
