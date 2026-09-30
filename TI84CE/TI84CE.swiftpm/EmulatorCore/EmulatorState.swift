import Foundation

/// A complete snapshot of the emulated machine: enough to resume execution exactly
/// where it left off, including the (possibly OS-modified) flash contents.
public struct EmulatorState: Codable {
    public static let formatVersion = 1

    public var version = EmulatorState.formatVersion
    /// SHA-256 of the ROM the snapshot was taken with.
    public var romHash: String
    public var cpu: CPU.State
    public var memory: MemoryState
    public var hardware: HardwareState

    public struct MemoryState: Codable {
        public var ram: Data
        /// Flash sectors that differ from the ROM image (sector start -> contents).
        public var flashDiff: [UInt32: Data]
        public var flashMode: Flash.Mode
    }

    public struct HardwareState: Codable {
        public var scheduler: Scheduler.State
        public var control: ControlPorts.State
        public var flashController: [UInt8]
        public var sha256: SHA256Accelerator.Snapshot
        public var usb: [UInt8]
        public var lcd: LCDController.State
        public var panel: LCDPanel.State
        public var interrupts: InterruptController.State
        public var watchdog: Watchdog.State
        public var timers: GeneralPurposeTimers.State
        public var rtc: RealTimeClock.State
        public var protectedPorts: [UInt8]
        public var keypad: Keypad.State
        public var backlight: [UInt8]
        public var spi: SPIController.State
        public var misc: [[UInt8]]
    }
}

public enum StateError: Error, CustomStringConvertible {
    case noROM
    case romMismatch
    case unsupportedVersion(Int)

    public var description: String {
        switch self {
        case .noROM: return "No ROM is loaded."
        case .romMismatch: return "This save state was made with a different ROM."
        case .unsupportedVersion(let v): return "Unsupported save state version \(v)."
        }
    }
}

extension Emulator {
    /// Captures the complete machine state.
    public func saveState() throws -> EmulatorState {
        guard let rom else { throw StateError.noROM }
        let ramData = Data(bytes: ram.bytes, count: RAM.size)
        return EmulatorState(
            romHash: rom.sha256,
            cpu: cpu.state,
            memory: .init(ram: ramData, flashDiff: flashDiff(against: rom), flashMode: flash.mode),
            hardware: .init(
                scheduler: scheduler.state,
                control: control.state,
                flashController: flashController.state,
                sha256: sha256.snapshot,
                usb: linkPort.regs,
                lcd: lcd.state,
                panel: panel.state,
                interrupts: interrupts.state,
                watchdog: watchdog.state,
                timers: timers.state,
                rtc: rtc.state,
                protectedPorts: protectedPorts.regs,
                keypad: keypad.state,
                backlight: backlight.regs,
                spi: spi.state,
                misc: [cxxx.regs, uart.regs, fxxx.regs]
            )
        )
    }

    /// Restores a snapshot produced by `saveState()` with the same ROM.
    public func loadState(_ s: EmulatorState) throws {
        guard let rom else { throw StateError.noROM }
        guard s.version == EmulatorState.formatVersion else { throw StateError.unsupportedVersion(s.version) }
        guard s.romHash == rom.sha256 else { throw StateError.romMismatch }

        flash.load(rom.data)
        applyFlashDiff(s.memory.flashDiff)
        s.memory.ram.withUnsafeBytes { raw in
            ram.bytes.update(from: raw.bindMemory(to: UInt8.self).baseAddress!, count: min(raw.count, RAM.size))
        }

        let h = s.hardware
        control.state = h.control
        flashController.state = h.flashController
        sha256.snapshot = h.sha256
        linkPort.regs = h.usb
        panel.state = h.panel
        lcd.state = h.lcd
        watchdog.state = h.watchdog
        rtc.state = h.rtc
        protectedPorts.regs = h.protectedPorts
        keypad.state = h.keypad
        backlight.regs = h.backlight
        spi.state = h.spi
        if h.misc.count == 3 { cxxx.regs = h.misc[0]; uart.regs = h.misc[1]; fxxx.regs = h.misc[2] }
        cpu.state = s.cpu
        scheduler.state = h.scheduler
        timers.state = h.timers
        interrupts.state = h.interrupts        // last: recomputes the CPU IRQ line
        keypad.releaseAll()
        lcd.render()
    }

    /// 64 KiB-granular difference between current flash and the pristine ROM.
    public func flashDiff(against rom: ROMImage) -> [UInt32: Data] {
        var diff: [UInt32: Data] = [:]
        let sector = 0x10000
        rom.data.withUnsafeBufferPointer { orig in
            var start = 0
            while start < Flash.size {
                if memcmp(orig.baseAddress! + start, flash.bytes + start, sector) != 0 {
                    diff[UInt32(start)] = Data(bytes: flash.bytes + start, count: sector)
                }
                start += sector
            }
        }
        return diff
    }

    public func applyFlashDiff(_ diff: [UInt32: Data]) {
        for (start, data) in diff where Int(start) + data.count <= Flash.size {
            data.withUnsafeBytes { raw in
                (flash.bytes + Int(start)).update(from: raw.bindMemory(to: UInt8.self).baseAddress!, count: data.count)
            }
        }
    }

    // MARK: Binary encoding

    public static func encode(_ state: EmulatorState) throws -> Data {
        let enc = PropertyListEncoder()
        enc.outputFormat = .binary
        return try enc.encode(state)
    }

    public static func decode(_ data: Data) throws -> EmulatorState {
        try PropertyListDecoder().decode(EmulatorState.self, from: data)
    }
}
