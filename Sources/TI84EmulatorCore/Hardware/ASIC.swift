/// The TI-84 Plus ASIC's system-control ports: status, interrupt mask and
/// status, Flash protection, CPU speed, execution limits, delay
/// configuration, the MD5 accelerator, the real-time clock and (inert) USB.
///
/// Other ASIC functions live in their own components and are mapped
/// directly on the I/O bus: the keypad (01h), memory mapper (05h–07h, 0Eh,
/// 0Fh, 27h, 28h), link port (00h, 08h–0Dh), LCD (10h–13h) and crystal
/// timers (30h–38h).
public final class ASIC: IODevice {
    public let profile: HardwareProfile
    unowned let clock: EmulatorClock
    unowned let scheduler: Scheduler
    unowned let interrupts: InterruptController
    unowned let mapper: MemoryMapper
    unowned let flash: FlashChip
    unowned let keyboard: KeyboardMatrix
    unowned let hardwareTimers: HardwareTimers
    unowned let crystalTimers: CrystalTimers
    unowned let lcd: T6A04

    /// Raw values of the simple configuration registers, indexed by port.
    public private(set) var registers = [UInt8](repeating: 0, count: 256)

    // MD5 accelerator: registers A, B, C, D, X, T, shift and function.
    private var md5 = [UInt32](repeating: 0, count: 6)
    private var md5Shift: UInt8 = 0
    private var md5Mode: UInt8 = 0

    // Real-time clock (84+ only): 32-bit seconds counter.
    private var rtcControl: UInt8 = 0
    private var rtcInput: UInt32 = 0
    private var rtcBase: UInt32 = 0
    private var rtcBaseTick: UInt64 = 0

    /// LCD "wait" flag of port 02h bit 1, active for a while after each LCD
    /// access when running at 15 MHz.
    private var lcdWaitUntil: UInt64 = 0

    /// Reports writes to protected ports and other oddities.
    public var eventHandler: ((String) -> Void)?

    init(profile: HardwareProfile, clock: EmulatorClock, scheduler: Scheduler,
         interrupts: InterruptController, mapper: MemoryMapper, flash: FlashChip,
         keyboard: KeyboardMatrix, hardwareTimers: HardwareTimers,
         crystalTimers: CrystalTimers, lcd: T6A04) {
        self.profile = profile
        self.clock = clock
        self.scheduler = scheduler
        self.interrupts = interrupts
        self.mapper = mapper
        self.flash = flash
        self.keyboard = keyboard
        self.hardwareTimers = hardwareTimers
        self.crystalTimers = crystalTimers
        self.lcd = lcd
    }

    /// Ports this device answers.
    static var ports: [UInt8] {
        var ports: [UInt8] = [0x02, 0x03, 0x04, 0x14, 0x15, 0x16, 0x17, 0x39]
        ports += Array(UInt8(0x18)...UInt8(0x1F))
        ports += Array(UInt8(0x20)...UInt8(0x26))
        ports += Array(UInt8(0x29)...UInt8(0x2F))
        ports += Array(UInt8(0x40)...UInt8(0x5F))
        return ports
    }

    func reset() {
        registers = [UInt8](repeating: 0, count: 256)
        registers[0x21] = profile.port21Reset
        registers[0x22] = 0x08
        registers[0x23] = profile.port23Reset
        registers[0x25] = 0x10
        registers[0x26] = 0x20
        registers[0x29] = 0x14
        registers[0x2A] = 0x27
        registers[0x2B] = 0x2F
        registers[0x2C] = 0x3B
        registers[0x2D] = 0x01
        registers[0x2E] = 0x44
        registers[0x2F] = 0x4A
        md5 = [UInt32](repeating: 0, count: 6)
        md5Shift = 0
        md5Mode = 0
        lcdWaitUntil = 0
        flash.overrideGroup = profile.flashOverrideGroupReset
        clock.setSpeed(.mhz6)
        updateDelays()
    }

    // MARK: IODevice

    public func read(port: UInt8) -> UInt8 {
        switch port {
        case 0x02:
            let lcdReady: UInt8 = clock.cpu.cycles >= lcdWaitUntil ? 0x02 : 0x00
            return profile.statusPortBase | lcdReady | (flash.unlocked ? 0x04 : 0x00)
        case 0x03:
            return interrupts.enableMask
        case 0x04:
            var v: UInt8 = keyboard.onKeyDown ? 0x00 : 0x08
            v |= UInt8(truncatingIfNeeded: interrupts.pending.rawValue) & 0x17
            v |= crystalTimers.finishedBits
            return v
        case 0x15:
            return profile.asicVersion
        case 0x1C...0x1F:
            return UInt8(truncatingIfNeeded: md5Result >> (UInt32(port - 0x1C) * 8))
        case 0x20:
            return registers[0x20] & 0x03
        case 0x21:
            return registers[0x21] & 0x33
        case 0x2D:
            return registers[0x2D] & 0x03
        case 0x22, 0x23, 0x25, 0x26, 0x29...0x2C, 0x2E, 0x2F:
            return registers[Int(port)]
        case 0x39:
            return 0xF0
        case 0x40...0x48:
            return profile.hasClock ? readClock(port) : 0
        case 0x4C:
            return profile.hasUSB ? 0x22 : 0   // no USB cable attached
        case 0x4D:
            return profile.hasUSB ? 0xA5 : 0
        case 0x55:
            return profile.hasUSB ? 0x1F : 0
        case 0x57:
            return profile.hasUSB ? 0x50 : 0
        default:
            return 0x00
        }
    }

    public func write(port: UInt8, value: UInt8) {
        switch port {
        case 0x02:
            interrupts.writeAcknowledge(value)
        case 0x03:
            interrupts.writeEnableMask(value)
            crystalTimers.setHaltSuppression(fromPort03: value)
        case 0x04:
            registers[0x04] = value
            mapper.setMode(fromPort04: value)
            hardwareTimers.setFrequency(fromPort04: value)
        case 0x14:
            if mapper.isPrivilegedWriteAllowed {
                flash.unlocked = value & 0x01 != 0
                eventHandler?(flash.unlocked ? "Flash unlocked" : "Flash locked")
            } else {
                eventHandler?("Write to protected port 14h ignored (not from privileged code)")
            }
        case 0x16, 0x17:
            registers[Int(port)] = value
        case 0x18...0x1D:
            let r = Int(port - 0x18)
            md5[r] = (md5[r] >> 8) | UInt32(value) << 24
        case 0x1E:
            md5Shift = value & 0x1F
        case 0x1F:
            md5Mode = value & 0x03
        case 0x20:
            registers[0x20] = value
            clock.setSpeed(value & 0x03 != 0 ? .mhz15 : .mhz6)
            scheduler.refreshRunLimit()
            updateDelays()
        case 0x21, 0x22, 0x23, 0x25, 0x26:
            if flash.unlocked {
                registers[Int(port)] = value
                if port == 0x21 { flash.overrideGroup = value & 0x03 }
            } else {
                eventHandler?("Write to protected port \(hex(port))h ignored (Flash locked)")
            }
        case 0x24:
            break
        case 0x29...0x2F:
            registers[Int(port)] = value
            updateDelays()
        case 0x40...0x44:
            if profile.hasClock { writeClock(port, value) }
        default:
            break
        }
    }

    // MARK: Delays

    /// Recomputes the LCD port wait states for the current CPU speed
    /// (ports 29h–2Ch hold one configuration per speed setting).
    private func updateDelays() {
        let speedIndex = Int(registers[0x20] & 0x03)
        let lcdConfig = registers[0x29 + speedIndex]
        lcd.portDelayCycles = speedIndex == 0 ? 0 : UInt64(lcdConfig >> 2)
    }

    /// Called by the LCD port handler wrapper after each LCD access.
    func noteLCDAccess() {
        let speed = Int(registers[0x20] & 0x03)
        guard speed != 0 else { return }
        let config = registers[0x2F]
        let index: Int
        switch speed {
        case 1: index = Int(config & 0x03)
        case 2: index = Int((config >> 2) & 0x07)
        default: index = Int((config >> 5) & 0x07)
        }
        lcdWaitUntil = clock.cpu.cycles &+ UInt64(48 + 64 * index)
    }

    // MARK: MD5 accelerator

    /// b + ((a + f(b, c, d) + X + T) <<< s)
    private var md5Result: UInt32 {
        let a = md5[0], b = md5[1], c = md5[2], d = md5[3], x = md5[4], t = md5[5]
        let f: UInt32
        switch md5Mode {
        case 0: f = (b & c) | (~b & d)
        case 1: f = (b & d) | (c & ~d)
        case 2: f = b ^ c ^ d
        default: f = c ^ (b | ~d)
        }
        let sum = f &+ a &+ x &+ t
        let s = UInt32(md5Shift)
        let rotated = s == 0 ? sum : (sum << s) | (sum >> (32 - s))
        return rotated &+ b
    }

    // MARK: Real-time clock

    private var emulatedSeconds: UInt32 {
        UInt32(truncatingIfNeeded: (clock.now &- rtcBaseTick) / EmulatorClock.ticksPerSecond)
    }

    private var rtcValue: UInt32 {
        rtcControl & 0x01 != 0 ? rtcBase &+ emulatedSeconds : rtcBase
    }

    private func readClock(_ port: UInt8) -> UInt8 {
        switch port {
        case 0x40: return rtcControl
        case 0x41...0x44: return UInt8(truncatingIfNeeded: rtcInput >> (UInt32(port - 0x41) * 8))
        default: return UInt8(truncatingIfNeeded: rtcValue >> (UInt32(port - 0x45) * 8))
        }
    }

    private func writeClock(_ port: UInt8, _ value: UInt8) {
        switch port {
        case 0x40:
            let current = rtcValue
            if value & 0x02 != 0 && rtcControl & 0x02 == 0 {
                // Rising edge of bit 1 loads the input register.
                rtcBase = rtcInput
            } else {
                rtcBase = current
            }
            rtcBaseTick = clock.now
            rtcControl = value & 0x03
        default:
            let shift = UInt32(port - 0x41) * 8
            rtcInput = (rtcInput & ~(0xFF << shift)) | UInt32(value) << shift
        }
    }

    /// Advances the real-time clock, e.g. by the wall-clock time the app spent
    /// closed, so the calculator's clock keeps real time.
    public func advanceClock(bySeconds seconds: UInt32) {
        guard rtcControl & 0x01 != 0 else { return }
        rtcBase &+= seconds
    }

    // MARK: State

    var snapshot: ASICState {
        ASICState(registers: registers, md5: md5, md5Shift: md5Shift, md5Mode: md5Mode,
                  rtcControl: rtcControl, rtcInput: rtcInput, rtcValue: rtcValue)
    }

    func restore(_ s: ASICState) {
        if s.registers.count == 256 { registers = s.registers }
        md5 = s.md5
        md5Shift = s.md5Shift
        md5Mode = s.md5Mode
        rtcControl = s.rtcControl
        rtcInput = s.rtcInput
        rtcBase = s.rtcValue
        rtcBaseTick = clock.now
        clock.setSpeed(registers[0x20] & 0x03 != 0 ? .mhz15 : .mhz6)
        updateDelays()
    }
}

public struct ASICState: Codable, Equatable, Sendable {
    var registers: [UInt8]
    var md5: [UInt32]
    var md5Shift: UInt8
    var md5Mode: UInt8
    var rtcControl: UInt8
    var rtcInput: UInt32
    var rtcValue: UInt32
}

/// Routes LCD port accesses through the ASIC's wait-state logic.
final class LCDPortAdapter: IODevice {
    unowned let lcd: T6A04
    unowned let asic: ASIC

    init(lcd: T6A04, asic: ASIC) {
        self.lcd = lcd
        self.asic = asic
    }

    func read(port: UInt8) -> UInt8 {
        let v = lcd.read(port: port)
        asic.noteLCDAccess()
        return v
    }

    func write(port: UInt8, value: UInt8) {
        lcd.write(port: port, value: value)
        asic.noteLCDAccess()
    }
}
