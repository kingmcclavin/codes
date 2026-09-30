import Foundation

/// Identifiers for hardware events driven by the scheduler.
public enum SchedulerEvent: Int, CaseIterable, Codable {
    case osTimer      // 32 kHz-derived periodic "OS timer" interrupt
    case rtcTick      // RTC one-second tick
    case lcdFrame     // LCD controller frame boundary
    case keypadScan   // keypad controller row scan
    case gpt          // general purpose timers (match / overflow)
    case watchdog
}

/// Deterministic emulation clock.
///
/// Time is measured in *base ticks* of 1.536 GHz, chosen so that every clock on the
/// TI-84 Plus CE divides it exactly: 48/24/12/6 MHz CPU clocks are 32/64/128/256 ticks,
/// and the 32768 Hz crystal is 46875 ticks. CPU instructions advance `cycles`; the
/// current time is derived from the cycle count and the current CPU clock rate.
public final class Scheduler {
    public static let baseHz: UInt64 = 1_536_000_000
    public static let ticksPer32k: UInt64 = 46_875
    public static let ticksPer6MHz: UInt64 = 256

    /// clock[0] = total CPU cycles since power-on, clock[1] = stop cycle for the
    /// CPU's inner loop. Kept in raw memory: the CPU and bus update it on every
    /// memory access.
    public let clock: UnsafeMutablePointer<Int64>

    /// Total CPU cycles executed since power-on.
    public var cycles: Int64 {
        get { clock[0] }
        set { clock[0] = newValue }
    }
    /// The CPU stops its inner loop once `cycles >= stopCycles`.
    public var stopCycles: Int64 {
        get { clock[1] }
        set { clock[1] = newValue }
    }

    @exclusivity(unchecked) private var anchorTicks: UInt64 = 0
    @exclusivity(unchecked) private var anchorCycles: Int64 = 0
    @exclusivity(unchecked) public private(set) var ticksPerCycle: UInt64 = 256
    /// Cycle budget of the current `run` call.
    var runLimit: Int64 = 0

    private var deadlines = [UInt64](repeating: .max, count: SchedulerEvent.allCases.count)

    public init() {
        clock = .allocate(capacity: 2)
        clock.initialize(repeating: 0, count: 2)
    }

    deinit { clock.deallocate() }

    /// Current emulated time in base ticks.
    @inline(__always) public var now: UInt64 {
        anchorTicks &+ UInt64(cycles &- anchorCycles) &* ticksPerCycle
    }

    public var cpuHz: UInt64 { Scheduler.baseHz / ticksPerCycle }

    /// Changes the CPU clock. Pending events keep their absolute deadlines.
    public func setCPUClock(hz: UInt64) {
        let t = now
        anchorTicks = t
        anchorCycles = cycles
        ticksPerCycle = max(1, Scheduler.baseHz / hz)
        updateStop()
    }

    public func deadline(_ e: SchedulerEvent) -> UInt64 { deadlines[e.rawValue] }
    public func isScheduled(_ e: SchedulerEvent) -> Bool { deadlines[e.rawValue] != .max }

    public func schedule(_ e: SchedulerEvent, at ticks: UInt64) {
        deadlines[e.rawValue] = ticks
        updateStop()
    }

    public func schedule(_ e: SchedulerEvent, after ticks: UInt64) {
        schedule(e, at: now &+ ticks)
    }

    public func cancel(_ e: SchedulerEvent) {
        deadlines[e.rawValue] = .max
    }

    var nextDeadline: UInt64 { deadlines.min() ?? .max }

    /// Recomputes the cycle at which the CPU must yield to process the next event.
    public func updateStop() {
        let next = nextDeadline
        var stop = runLimit
        if next != .max {
            let t = now
            if next <= t {
                stop = cycles
            } else {
                let delta = (next - t + ticksPerCycle - 1) / ticksPerCycle
                if delta < UInt64(Int64.max / 2) { stop = min(stop, cycles + Int64(delta)) }
            }
        }
        stopCycles = stop
    }

    /// Returns the next event whose deadline has passed and unschedules it.
    func popDueEvent() -> SchedulerEvent? {
        let t = now
        var best: Int = -1
        var bestTime = UInt64.max
        for i in 0..<deadlines.count where deadlines[i] <= t && deadlines[i] < bestTime {
            best = i; bestTime = deadlines[i]
        }
        guard best >= 0 else { return nil }
        deadlines[best] = .max
        return SchedulerEvent(rawValue: best)
    }

    // MARK: State

    public struct State: Codable, Equatable {
        var cycles: Int64
        var anchorTicks: UInt64
        var anchorCycles: Int64
        var ticksPerCycle: UInt64
        var deadlines: [UInt64]
    }

    public var state: State {
        get { State(cycles: cycles, anchorTicks: anchorTicks, anchorCycles: anchorCycles, ticksPerCycle: ticksPerCycle, deadlines: deadlines) }
        set {
            cycles = newValue.cycles; anchorTicks = newValue.anchorTicks; anchorCycles = newValue.anchorCycles
            ticksPerCycle = newValue.ticksPerCycle
            if newValue.deadlines.count == deadlines.count { deadlines = newValue.deadlines }
            updateStop()
        }
    }

    public func reset() {
        cycles = 0; anchorTicks = 0; anchorCycles = 0; ticksPerCycle = 256
        for i in deadlines.indices { deadlines[i] = .max }
        runLimit = 0
        stopCycles = 0
    }
}
