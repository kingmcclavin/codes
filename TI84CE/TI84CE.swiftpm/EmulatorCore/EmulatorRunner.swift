import Foundation

/// Drives an `Emulator` on a dedicated thread, synchronised to the host clock.
///
///     Emulation thread                    UI / main thread
///     ────────────────                    ────────────────
///     drain commands + key events   ◀──  press(), release(), perform()
///     run CPU + peripherals for Δt
///     publish changed LCD frame     ──▶  latestFrame(newerThan:)
///     sleep until the next slice
///
/// The emulator itself is only ever touched on the emulation thread.
public final class EmulatorRunner {
    public enum RunState: Equatable {
        case running
        case paused
        case breakpoint(UInt32)
    }

    public let emulator: Emulator

    private let condition = NSCondition()
    // Guarded by `condition`:
    private var commands: [(Emulator) -> Void] = []
    private var pausedFlag = true
    private var stopFlag = false
    private var frame: LCDFrame?
    private var frameBrightness = 1.0
    private var measuredSpeed = 0.0

    // Emulation-thread state.
    private var thread: Thread?
    private var pressedAt: [KeyPosition: UInt64] = [:]
    private var pendingReleases: [(KeyPosition, UInt64)] = []

    /// 1.0 = real time. 0 = as fast as possible.
    public var speed: Double {
        get { condition.lock(); defer { condition.unlock() }; return speedValue }
        set { condition.lock(); speedValue = max(0, newValue); condition.unlock() }
    }
    private var speedValue = 1.0

    /// Minimum time a key stays down, in emulated seconds, so a quick tap is seen
    /// by at least one keypad scan of the ROM.
    public var minimumKeyHold = 0.05

    /// Called on the main thread when the run state changes (e.g. a breakpoint).
    public var onStateChange: ((RunState) -> Void)?
    /// Called on the main thread when the CPU reports an unsupported opcode.
    public var onDiagnostic: ((String) -> Void)?

    private let sliceSeconds = 1.0 / 120.0

    public init(emulator: Emulator) {
        self.emulator = emulator
        emulator.lcd.onFrame = { [unowned self] f in
            self.condition.lock()
            self.frame = f
            self.frameBrightness = self.emulator.backlight.brightness
            self.condition.unlock()
        }
        emulator.cpu.onUnsupported = { [weak self] msg in
            DispatchQueue.main.async { self?.onDiagnostic?(msg) }
        }
        frame = emulator.lcd.frame
    }

    deinit { stop() }

    // MARK: Lifecycle

    /// Starts the emulation thread (paused until `resume()`).
    public func start() {
        guard thread == nil else { return }
        let t = Thread { [unowned self] in self.loop() }
        t.name = "TI-84 CE emulation"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    public func stop() {
        condition.lock()
        stopFlag = true
        condition.signal()
        condition.unlock()
    }

    public func resume() {
        condition.lock()
        pausedFlag = false
        condition.signal()
        condition.unlock()
        notify(.running)
    }

    public func pause() {
        condition.lock()
        pausedFlag = true
        condition.unlock()
        notify(.paused)
    }

    public var isPaused: Bool {
        condition.lock(); defer { condition.unlock() }
        return pausedFlag
    }

    /// Emulated speed relative to real time over the last second (1.0 = 100%).
    public var currentSpeed: Double {
        condition.lock(); defer { condition.unlock() }
        return measuredSpeed
    }

    // MARK: Input

    public func press(_ key: CalculatorKey) { post(key.position, true) }
    public func release(_ key: CalculatorKey) { post(key.position, false) }

    /// Key events share the command queue so they stay ordered with commands.
    private func post(_ key: KeyPosition, _ down: Bool) {
        perform { [unowned self] _ in self.applyKey(key, down) }
    }

    // MARK: Commands

    /// Runs `block` on the emulation thread before the next slice.
    public func perform(_ block: @escaping (Emulator) -> Void) {
        condition.lock()
        commands.append(block)
        condition.signal()
        condition.unlock()
    }

    /// Runs `block` on the emulation thread and delivers its result on the main thread.
    public func query<T>(_ block: @escaping (Emulator) -> T, completion: @escaping (T) -> Void) {
        perform { emu in
            let value = block(emu)
            DispatchQueue.main.async { completion(value) }
        }
    }

    /// Runs `block` on the emulation thread and waits for its result. The runner must
    /// have been started. Used when the app is about to be suspended.
    public func sync<T>(_ block: @escaping (Emulator) -> T) -> T {
        let done = DispatchSemaphore(value: 0)
        var result: T?
        perform { emu in
            result = block(emu)
            done.signal()
        }
        done.wait()
        return result!
    }

    /// Executes a single instruction while paused (debugger).
    public func step(completion: (() -> Void)? = nil) {
        perform { emu in
            emu.cpu.ignoreBreakpointOnce = true
            emu.step()
            emu.lcd.render()
            if let completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    // MARK: Frames

    /// The latest LCD frame if it is newer than `serial`, plus the backlight level.
    public func latestFrame(newerThan serial: UInt64) -> (LCDFrame, Double)? {
        condition.lock(); defer { condition.unlock() }
        guard let f = frame, f.serial != serial else { return nil }
        return (f, frameBrightness)
    }

    // MARK: Emulation thread

    private func loop() {
        var last = Date()
        var windowStart = last
        var windowEmulated = 0.0

        while true {
            condition.lock()
            while !stopFlag && pausedFlag && commands.isEmpty {
                condition.wait()
            }
            if stopFlag { condition.unlock(); return }
            let work = commands
            let paused = pausedFlag
            let speed = speedValue
            commands.removeAll()
            condition.unlock()

            for c in work { c(emulator) }
            applyPendingReleases()

            if paused {
                last = Date()
                continue
            }

            // Run for the host time that elapsed (capped so a stall does not cause a
            // burst), scaled by the speed setting.
            let now = Date()
            let elapsed = min(now.timeIntervalSince(last), 0.1)
            last = now
            let budget: Double
            if speed == 0 {
                budget = runUnlimited()
            } else {
                budget = elapsed * speed
                if budget > 0 { emulator.run(seconds: budget) }
            }
            windowEmulated += budget

            if emulator.cpu.breakpointHit {
                condition.lock(); pausedFlag = true; condition.unlock()
                notify(.breakpoint(emulator.cpu.registers.pc))
            }

            let windowLength = now.timeIntervalSince(windowStart)
            if windowLength >= 1 {
                condition.lock(); measuredSpeed = windowEmulated / windowLength; condition.unlock()
                windowStart = now
                windowEmulated = 0
            }

            // Sleep for the remainder of the slice.
            let spent = Date().timeIntervalSince(now)
            if speed != 0 && spent < sliceSeconds {
                Thread.sleep(forTimeInterval: sliceSeconds - spent)
            }
        }
    }

    /// Unlimited speed: emulate in 1/60 s chunks for about one slice of host time.
    private func runUnlimited() -> Double {
        let start = Date()
        var emulated = 0.0
        repeat {
            emulator.run(seconds: 1.0 / 60.0)
            emulated += 1.0 / 60.0
            applyPendingReleases()
        } while Date().timeIntervalSince(start) < sliceSeconds && !emulator.cpu.breakpointHit
        return emulated
    }

    private func applyKey(_ key: KeyPosition, _ down: Bool) {
        let now = emulator.scheduler.now
        if down {
            pendingReleases.removeAll { $0.0 == key }
            pressedAt[key] = now
            emulator.setKey(key, pressed: true)
        } else {
            let hold = UInt64(minimumKeyHold * Double(Scheduler.baseHz))
            let earliest = (pressedAt[key] ?? 0) &+ hold
            if now >= earliest {
                emulator.setKey(key, pressed: false)
            } else {
                pendingReleases.append((key, earliest))
            }
            pressedAt[key] = nil
        }
    }

    private func applyPendingReleases() {
        guard !pendingReleases.isEmpty else { return }
        let now = emulator.scheduler.now
        pendingReleases.removeAll { entry in
            guard now >= entry.1 else { return false }
            emulator.setKey(entry.0, pressed: false)
            return true
        }
    }

    private func notify(_ state: RunState) {
        DispatchQueue.main.async { [weak self] in self?.onStateChange?(state) }
    }
}
