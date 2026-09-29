import Foundation

/// Tunables that do not change the emulated hardware itself.
public struct EmulatorConfiguration: Equatable, Sendable {
    /// LCD refresh rate used to publish frames.
    public var frameRate: Double = 60
    /// 0 = crisp 1-bit frames; up to ~0.9 = slow panel (grayscale-friendly).
    public var lcdPersistence: Double = 0
    /// Keys stay down for at least this long so a quick tap is never missed
    /// by the OS keyboard scan (which runs from the timer interrupt).
    public var minimumKeyPressSeconds: Double = 0.06
    /// Ignore LCD accesses made while the T6A04 reports busy, as hardware does.
    public var enforceLCDBusyTiming = false

    public init() {}
}

/// Why `Emulator.run` returned.
public enum RunResult: Equatable, Sendable {
    case completed
    case breakpoint(UInt16)
    case paused
}

/// A complete TI-84 Plus: CPU, memory, ASIC and peripherals, wired
/// together and driven by the event scheduler.
///
/// The calculator's behaviour comes entirely from the ROM; this class only
/// emulates hardware. It is not thread-safe: drive it from one thread
/// (see `EmulatorRunner`).
public final class Emulator {
    public let rom: ROMImage
    public var profile: HardwareProfile { rom.profile }
    public var configuration: EmulatorConfiguration {
        didSet { applyConfiguration() }
    }

    // Core
    public let memory: MemoryBus
    public let io: IOBus
    public let cpu: CPU
    public let clock: EmulatorClock
    public let scheduler: Scheduler

    // Memory
    public let ram: RAM
    public let flash: FlashChip
    public let mapper: MemoryMapper

    // Peripherals
    public let interrupts: InterruptController
    public let hardwareTimers: HardwareTimers
    public let crystalTimers: CrystalTimers
    public let lcd: T6A04
    public let keyboard: KeyboardMatrix
    public let link: LinkPort
    public let asic: ASIC
    private let lcdPort: LCDPortAdapter

    public let debugger = Debugger()
    public let frameBuilder = LCDFrameBuilder()

    /// Latest published LCD frame.
    public var frame: LCDFrame { frameBuilder.frame }
    /// Called (on the emulation thread) whenever a new LCD frame is published.
    public var onFrame: ((LCDFrame) -> Void)?
    /// Hardware/diagnostic messages (Flash operations, protected port writes,
    /// undefined opcodes).
    public var onEvent: ((String) -> Void)?

    private var keyPressedAt: [Key: UInt64] = [:]
    private var pendingReleases: [Key: UInt64] = [:]

    public init(rom: ROMImage, configuration: EmulatorConfiguration = EmulatorConfiguration()) {
        self.rom = rom
        self.configuration = configuration
        let profile = rom.profile

        memory = MemoryBus()
        io = IOBus()
        cpu = CPU(memory: memory, io: io)
        clock = EmulatorClock(cpu: cpu)
        scheduler = Scheduler(clock: clock)

        ram = RAM(pageCount: profile.ramPages)
        flash = FlashChip(image: rom)
        mapper = MemoryMapper(profile: profile, bus: memory, flash: flash, ram: ram)

        interrupts = InterruptController(cpu: cpu)
        hardwareTimers = HardwareTimers(scheduler: scheduler, interrupts: interrupts)
        crystalTimers = CrystalTimers(clock: clock, scheduler: scheduler, interrupts: interrupts)
        lcd = T6A04(clock: clock)
        keyboard = KeyboardMatrix()
        link = LinkPort(interrupts: interrupts)
        asic = ASIC(profile: profile, clock: clock, scheduler: scheduler, interrupts: interrupts,
                    mapper: mapper, flash: flash, keyboard: keyboard, hardwareTimers: hardwareTimers,
                    crystalTimers: crystalTimers, lcd: lcd)
        lcdPort = LCDPortAdapter(lcd: lcd, asic: asic)

        io.map(0x00, to: link)
        io.map(0x01, to: keyboard)
        io.map([0x05, 0x06, 0x07, 0x0E, 0x0F, 0x27, 0x28], to: mapper)
        io.map(0x08...0x0D, to: link)
        io.map(0x10...0x13, to: lcdPort)
        io.map(0x30...0x38, to: crystalTimers)
        io.map(ASIC.ports, to: asic)
        // Ports 60h–7Fh mirror 40h–5Fh on the 84+ ASIC.
        for port in UInt8(0x60)...UInt8(0x7F) {
            if let device = io.device(for: port - 0x20) { io.map(port, to: device) }
        }
        io.cycleSource = { [unowned cpu] in cpu.cycles }

        keyboard.onKeyChanged = { [unowned self] _ in
            // The ON key interrupts on both press and release edges.
            if interrupts.onKeyEnabled { interrupts.raise(.onKey) }
        }
        scheduler.setHandler(.lcdFrame) { [unowned self] due in
            publishFrame()
            scheduler.schedule(.lcdFrame, at: due &+ frameInterval)
        }
        cpu.diagnosticHandler = { [unowned self] in onEvent?($0.description) }
        flash.eventHandler = { [unowned self] in onEvent?($0) }
        asic.eventHandler = { [unowned self] in onEvent?($0) }

        applyConfiguration()
        reset()
    }

    private var frameInterval: UInt64 {
        UInt64(Double(EmulatorClock.ticksPerSecond) / max(1, configuration.frameRate))
    }

    private func applyConfiguration() {
        frameBuilder.persistence = min(max(configuration.lcdPersistence, 0), 0.95)
        lcd.enforceBusyTiming = configuration.enforceLCDBusyTiming
    }

    // MARK: - Lifecycle

    /// Hardware reset (like removing and reinserting the batteries while
    /// keeping RAM and Flash contents). The CPU starts in the boot code.
    public func reset() {
        cpu.reset()
        flash.reset()
        mapper.reset()
        interrupts.reset()
        keyboard.reset()
        lcd.reset()
        link.reset()
        crystalTimers.reset()
        asic.reset()
        hardwareTimers.reset()
        // The ASIC starts executing the boot page mapped at 8000h.
        cpu.registers.pc = 0x8000
        scheduler.schedule(.lcdFrame, after: frameInterval)
        frameBuilder.invalidate()
        publishFrame()
    }

    /// Clears RAM and resets, so the OS reinitialises memory ("RAM cleared").
    public func clearRAMAndReset() {
        ram.fill(0x00)
        reset()
    }

    /// Restores the Flash chip to the pristine ROM image (erasing the archive).
    public func restoreFactoryFlash() {
        flash.load(rom.bytes)
        flash.isDirty = true
    }

    // MARK: - Execution

    /// Runs for `ticks` of emulated time (see `EmulatorClock.ticksPerSecond`).
    @discardableResult
    public func run(forTicks ticks: UInt64) -> RunResult {
        run(untilTick: clock.now &+ ticks)
    }

    @discardableResult
    public func run(seconds: Double) -> RunResult {
        run(forTicks: UInt64(seconds * Double(EmulatorClock.ticksPerSecond)))
    }

    @discardableResult
    public func run(untilTick target: UInt64) -> RunResult {
        debugger.pauseRequested = false
        while clock.now < target {
            processPendingReleases()
            let sliceEnd = min(target, scheduler.nextDeadline)
            let cycleTarget = clock.cycle(atTick: sliceEnd)

            if debugger.isActive {
                if let result = runWithDebugger(untilCycle: cycleTarget) { return result }
            } else {
                cpu.run(until: cycleTarget)
            }
            scheduler.fireDue()
            if debugger.pauseRequested { return .paused }
        }
        return .completed
    }

    /// Instruction-by-instruction execution with breakpoint checks.
    private func runWithDebugger(untilCycle target: UInt64) -> RunResult? {
        while cpu.cycles < target {
            let pc = cpu.registers.pc
            if debugger.shouldBreak(at: pc) && !cpu.halted {
                return .breakpoint(pc)
            }
            if cpu.isIdleHalted {
                cpu.run(until: target)
                break
            }
            cpu.step()
            debugger.recordStep(pc: pc)
            if debugger.pauseRequested { return .paused }
        }
        return nil
    }

    /// Executes exactly one instruction (or interrupt acknowledge), firing
    /// any hardware events that become due.
    @discardableResult
    public func stepInstruction() -> Int {
        let pc = cpu.registers.pc
        let t = cpu.step()
        debugger.recordStep(pc: pc)
        debugger.skipBreakpointOnce = cpu.registers.pc
        scheduler.fireDue()
        return t
    }

    // MARK: - Keypad

    /// Presses or releases a key on the emulated keypad matrix. The ROM's
    /// keyboard scanning code sees the change on port 01h (or, for ON,
    /// through the interrupt controller).
    public func setKey(_ key: Key, pressed: Bool) {
        let now = clock.now
        if pressed {
            pendingReleases[key] = nil
            keyPressedAt[key] = now
            keyboard.setKey(key, pressed: true)
        } else {
            let minimum = UInt64(configuration.minimumKeyPressSeconds * Double(EmulatorClock.ticksPerSecond))
            if let pressedAt = keyPressedAt[key], now &- pressedAt < minimum {
                pendingReleases[key] = pressedAt &+ minimum
            } else {
                keyboard.setKey(key, pressed: false)
                keyPressedAt[key] = nil
            }
        }
    }

    public func releaseAllKeys() {
        pendingReleases.removeAll()
        keyPressedAt.removeAll()
        keyboard.releaseAll()
    }

    private func processPendingReleases() {
        guard !pendingReleases.isEmpty else { return }
        let now = clock.now
        for (key, releaseAt) in pendingReleases where releaseAt <= now {
            pendingReleases[key] = nil
            keyPressedAt[key] = nil
            keyboard.setKey(key, pressed: false)
        }
    }

    // MARK: - Display

    private func publishFrame() {
        if frameBuilder.sample(lcd) {
            onFrame?(frameBuilder.frame)
        }
    }

    // MARK: - Convenience

    /// Seconds of emulated time since power-on.
    public var emulatedSeconds: Double {
        Double(clock.now) / Double(EmulatorClock.ticksPerSecond)
    }

    /// Whether the calculator appears to be switched off (LCD off, CPU halted
    /// waiting for the ON key).
    public var isPoweredDown: Bool {
        !lcd.displayOn && cpu.halted && !interrupts.timer1Enabled && !interrupts.timer2Enabled
    }
}
