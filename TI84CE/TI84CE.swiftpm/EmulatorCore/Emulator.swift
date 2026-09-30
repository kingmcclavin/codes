import Foundation

/// A complete TI-84 Plus CE: eZ80 CPU, memory, and every peripheral the ROM uses.
///
/// `Emulator` is single-threaded; `EmulatorRunner` drives it from a dedicated
/// emulation thread and exchanges input and frames with the UI.
public final class Emulator {
    public let scheduler = Scheduler()
    public let flash = Flash()
    public let ram = RAM()
    public let io = IOBus()
    public let bus: MemoryBus
    public let cpu: CPU

    public let control: ControlPorts
    public let flashController: FlashController
    public let sha256 = SHA256Accelerator()
    public let linkPort = LinkPort()
    public let panel = LCDPanel()
    public let lcd: LCDController
    public let interrupts: InterruptController
    public let watchdog = Watchdog()
    public let timers: GeneralPurposeTimers
    public let rtc: RealTimeClock
    public let protectedPorts = RegisterFileDevice(size: 0x100)
    public let keypad: Keypad
    public let backlight = Backlight()
    public let cxxx = RegisterFileDevice(size: 0x100)
    public let spi: SPIController
    public let uart = RegisterFileDevice(size: 0x100)
    public let fxxx = RegisterFileDevice(size: 0x100)

    public private(set) var rom: ROMImage?

    /// CPU clock rates selectable through control port 0x01.
    public static let cpuClocks: [UInt64] = [6_000_000, 12_000_000, 24_000_000, 48_000_000]

    /// OS timer periods in 32 kHz ticks, selected by control port 0x00 bits 0-1.
    static let osTimerPeriods: [UInt64] = [74, 154, 218, 314]

    public init() {
        bus = MemoryBus(flash: flash, ram: ram, io: io, scheduler: scheduler)
        cpu = CPU(bus: bus, scheduler: scheduler)
        interrupts = InterruptController(cpu: cpu)
        control = ControlPorts()
        flashController = FlashController(bus: bus)
        lcd = LCDController(scheduler: scheduler, interrupts: interrupts, bus: bus, panel: panel)
        timers = GeneralPurposeTimers(scheduler: scheduler, interrupts: interrupts)
        rtc = RealTimeClock(interrupts: interrupts)
        keypad = Keypad(scheduler: scheduler, interrupts: interrupts)
        spi = SPIController(panel: panel)

        io.attach(control, at: 0x0)
        io.attach(flashController, at: 0x1)
        io.attach(sha256, at: 0x2)
        io.attach(linkPort, at: 0x3)
        io.attach(lcd, at: 0x4)
        io.attach(interrupts, at: 0x5)
        io.attach(watchdog, at: 0x6)
        io.attach(timers, at: 0x7)
        io.attach(rtc, at: 0x8)
        io.attach(protectedPorts, at: 0x9)
        io.attach(keypad, at: 0xA)
        io.attach(backlight, at: 0xB)
        io.attach(cxxx, at: 0xC)
        io.attach(spi, at: 0xD)
        io.attach(uart, at: 0xE)
        io.attach(fxxx, at: 0xF)

        control.onCPUSpeedChange = { [unowned self] index in self.setCPUSpeed(index) }
    }

    public convenience init(rom: ROMImage) {
        self.init()
        load(rom: rom)
    }

    /// Installs a ROM image into flash and performs a power-on reset.
    public func load(rom: ROMImage) {
        self.rom = rom
        flash.load(rom.data)
        powerOn(clearRAM: true)
    }

    /// Hardware reset. `clearRAM` models a cold start (all RAM zero); a warm reset
    /// keeps RAM, like pressing the reset button with batteries in.
    public func powerOn(clearRAM: Bool) {
        scheduler.reset()
        if clearRAM { ram.clear() }
        flash.resetCommandState()
        panel.reset()
        io.resetAll()
        cpu.reset()
        setCPUSpeed(0)
        scheduleOSTimer()
        scheduler.schedule(.rtcTick, after: Scheduler.baseHz)
    }

    public func reset() { powerOn(clearRAM: false) }

    private func setCPUSpeed(_ index: UInt8) {
        timers.willChangeCPUClock()
        scheduler.setCPUClock(hz: Emulator.cpuClocks[Int(index & 3)])
        timers.didChangeCPUClock()
    }

    private func scheduleOSTimer() {
        let period = Emulator.osTimerPeriods[Int(control.ports[0] & 3)]
        scheduler.schedule(.osTimer, after: period * Scheduler.ticksPer32k)
    }

    // MARK: - Execution

    /// Runs the whole system for `cycles` CPU cycles (or until a breakpoint).
    /// Returns the number of cycles actually executed.
    @discardableResult
    public func run(cycles: Int) -> Int {
        let start = scheduler.cycles
        let limit = start + Int64(cycles)
        scheduler.runLimit = limit
        while scheduler.cycles < limit {
            processEvents()
            scheduler.runLimit = limit
            scheduler.updateStop()
            cpu.execute()
            if cpu.breakpointHit { break }
        }
        processEvents()
        return Int(scheduler.cycles - start)
    }

    /// Runs for the given amount of emulated time.
    @discardableResult
    public func run(seconds: Double) -> Int {
        run(cycles: Int(Double(scheduler.cpuHz) * seconds))
    }

    /// Executes exactly one instruction (debugger), processing due events first.
    public func step() {
        processEvents()
        scheduler.runLimit = scheduler.cycles + 1_000_000
        cpu.debugStep()
        processEvents()
    }

    private func processEvents() {
        while let e = scheduler.popDueEvent() {
            switch e {
            case .osTimer:
                interrupts.pulse(InterruptSource.osTimer)
                scheduleOSTimer()
            case .rtcTick:
                rtc.tick()
                scheduler.schedule(.rtcTick, after: Scheduler.baseHz)
            case .lcdFrame:
                lcd.handleEvent()
            case .keypadScan:
                keypad.handleEvent()
            case .gpt:
                timers.handleEvent()
            case .watchdog:
                break
            }
        }
    }

    // MARK: - Input

    public func setKey(_ key: CalculatorKey, pressed: Bool) {
        keypad.setKey(key.position, pressed: pressed)
    }

    public func setKey(_ position: KeyPosition, pressed: Bool) {
        keypad.setKey(position, pressed: pressed)
    }

    // MARK: - Diagnostics

    /// Register / state summary in the form the debugger and tests print.
    public var debugDescription: String {
        let r = cpu.registers
        let op = (0..<4).map { String(format: "%02X", bus.peek(cpu.adl ? r.pc &+ UInt32($0) : (UInt32(r.mbase) << 16) | ((r.pc &+ UInt32($0)) & 0xFFFF))) }.joined(separator: " ")
        return String(format: "PC=%06X SP=%06X AF=%04X BC=%06X DE=%06X HL=%06X IX=%06X IY=%06X ",
                      r.pc, cpu.adl ? r.spl : r.sps, r.af, r.bc, r.de, r.hl, r.ix, r.iy)
            + "F=\(Flag.describe(r.f)) ADL=\(cpu.adl ? 1 : 0) IEF=\(cpu.ief1 ? 1 : 0) IM=\(cpu.im)"
            + (cpu.halted ? " HALT" : "") + " op=[\(op)] cyc=\(scheduler.cycles)"
    }
}
