import Foundation

/// Runs an `Emulator` on its own thread in real time.
///
/// All access to the emulator happens on the emulation thread. Other threads
/// communicate through `send` (fire-and-forget) and `sync` (blocking call),
/// and receive LCD frames through `onFrame` (called on the emulation thread;
/// hop to the main thread before touching UI).
///
///     UI thread ── key events / commands ──▶ emulation thread
///     emulation thread: CPU cycles → hardware events → LCD frames ──▶ onFrame
public final class EmulatorRunner: @unchecked Sendable {
    public enum Status: Equatable, Sendable {
        case running
        case paused
        case breakpoint(UInt16)
        case stopped
    }

    public let emulator: Emulator

    /// 1.0 = real-time; 2.0 = double speed; 0 = as fast as possible.
    public var speedMultiplier: Double {
        get { lock.withLock { _speedMultiplier } }
        set { lock.withLock { _speedMultiplier = max(0, newValue); resetPacing = true } }
    }

    /// Called on the emulation thread with each new LCD frame.
    public var onFrame: ((LCDFrame) -> Void)?
    /// Called on the emulation thread when the run status changes.
    public var onStatusChange: ((Status) -> Void)?

    public var status: Status { lock.withLock { _status } }

    private let lock = NSCondition()
    private var queue: [(Emulator) -> Void] = []
    private var _status: Status = .paused
    private var _speedMultiplier: Double = 1
    private var resetPacing = true
    private var thread: Thread?
    private var shouldExit = false

    /// Emulated time per scheduling slice.
    private let sliceSeconds = 1.0 / 120.0

    public init(emulator: Emulator) {
        self.emulator = emulator
        emulator.onFrame = { [weak self] frame in self?.onFrame?(frame) }
    }

    deinit {
        stop()
    }

    /// Starts the emulation thread (paused or running).
    public func start(running: Bool = true) {
        lock.withLock {
            guard thread == nil else { return }
            shouldExit = false
            _status = running ? .running : .paused
            resetPacing = true
            let t = Thread { [weak self] in self?.threadMain() }
            t.name = "TI-84 Emulation"
            t.qualityOfService = .userInteractive
            thread = t
            t.start()
        }
    }

    /// Stops the thread. Pending commands are still executed.
    public func stop() {
        lock.withLock {
            shouldExit = true
            lock.broadcast()
        }
        while lock.withLock({ thread != nil }) {
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    public func resume() { setStatus(.running) }
    public func pause() { setStatus(.paused) }

    /// Executes one instruction while paused.
    public func stepInstruction() {
        send { $0.stepInstruction() }
    }

    /// Queues work to run on the emulation thread.
    public func send(_ work: @escaping (Emulator) -> Void) {
        lock.withLock {
            queue.append(work)
            lock.broadcast()
        }
    }

    /// Runs `work` on the emulation thread and waits for its result.
    /// Must not be called from the emulation thread itself.
    public func sync<T>(_ work: @escaping (Emulator) -> T) -> T {
        if Thread.current == thread { return work(emulator) }
        guard lock.withLock({ thread != nil }) else { return work(emulator) }
        let done = NSCondition()
        var result: T?
        send { emulator in
            let value = work(emulator)
            done.withLock {
                result = value
                done.broadcast()
            }
        }
        return done.withLock {
            while result == nil { done.wait() }
            return result!
        }
    }

    public func setKey(_ key: Key, pressed: Bool) {
        send { $0.setKey(key, pressed: pressed) }
    }

    // MARK: - Thread

    private func setStatus(_ status: Status) {
        lock.withLock {
            _status = status
            resetPacing = true
            lock.broadcast()
        }
        onStatusChange?(status)
    }

    private func threadMain() {
        var wallStart = Date()
        var emulatedStart = emulator.clock.now

        while true {
            let (work, status, speed, exit, repace) = lock.withLock { () -> ([(Emulator) -> Void], Status, Double, Bool, Bool) in
                while queue.isEmpty && _status != .running && !shouldExit {
                    lock.wait()
                }
                let pending = queue
                queue.removeAll()
                let repace = resetPacing
                resetPacing = false
                return (pending, _status, _speedMultiplier, shouldExit, repace)
            }
            for item in work { item(emulator) }
            if exit { break }
            guard status == .running else { continue }

            if repace {
                wallStart = Date()
                emulatedStart = emulator.clock.now
            }

            let result = emulator.run(seconds: sliceSeconds)
            if case let .breakpoint(address) = result {
                lock.withLock { _status = .breakpoint(address) }
                onStatusChange?(.breakpoint(address))
                continue
            }

            // Pace emulated time against wall-clock time.
            guard speed > 0 else { continue }
            let emulatedElapsed = Double(emulator.clock.now &- emulatedStart) / Double(EmulatorClock.ticksPerSecond)
            let target = wallStart.addingTimeInterval(emulatedElapsed / speed)
            let ahead = target.timeIntervalSinceNow
            if ahead > 0 {
                Thread.sleep(forTimeInterval: ahead)
            } else if ahead < -0.25 {
                // Too far behind (device busy, debugger): don't try to catch up.
                lock.withLock { resetPacing = true }
            }
        }

        lock.withLock {
            thread = nil
            _status = .stopped
        }
        onStatusChange?(.stopped)
    }
}

extension NSCondition {
    @discardableResult
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
