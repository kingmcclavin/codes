import Foundation

/// Everything needed to resume the calculator exactly where it was.
public struct EmulatorState: Codable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion = EmulatorState.currentFormatVersion
    /// SHA-256 of the ROM the state was captured with.
    public var romSHA256: String
    public var model: CalculatorModel
    /// Wall-clock time of the capture (used to advance the calculator clock).
    public var savedAt: Date

    public var cpu: CPUState
    public var memory: MemoryState
    public var hardware: HardwareState
}

public struct MemoryState: Codable, Sendable {
    public var ram: Data
    /// Full Flash contents (OS + archive). The original ROM image is untouched.
    public var flash: Data
    var flashChip: FlashState
    var mapper: MapperState
}

public struct HardwareState: Codable, Sendable {
    var clock: ClockState
    var schedulerDeadlines: [UInt64]
    var interrupts: InterruptState
    var hardwareTimerPeriod: Int
    var crystalTimers: [CrystalTimers.Timer]
    var lcd: LCDState
    var keyboard: KeyboardState
    var link: LinkState
    var asic: ASICState
}

public enum EmulatorStateError: Error, CustomStringConvertible {
    case romMismatch(expected: String, actual: String)
    case unsupportedFormat(Int)
    case corrupt(String)

    public var description: String {
        switch self {
        case .romMismatch:
            return "This save state was created with a different ROM."
        case let .unsupportedFormat(v):
            return "Save state format \(v) is not supported."
        case let .corrupt(reason):
            return "Save state is damaged: \(reason)"
        }
    }
}

extension Emulator {
    /// Captures the complete machine state.
    public func saveState() -> EmulatorState {
        EmulatorState(
            romSHA256: rom.sha256,
            model: profile.model,
            savedAt: Date(),
            cpu: cpu.state,
            memory: MemoryState(ram: Data(ram.storage), flash: Data(flash.storage),
                                flashChip: flash.snapshot, mapper: mapper.snapshot),
            hardware: HardwareState(
                clock: clock.snapshot,
                schedulerDeadlines: scheduler.snapshot,
                interrupts: interrupts.snapshot,
                hardwareTimerPeriod: hardwareTimers.snapshot,
                crystalTimers: crystalTimers.snapshot,
                lcd: lcd.snapshot,
                keyboard: keyboard.snapshot,
                link: link.snapshot,
                asic: asic.snapshot))
    }

    /// Restores a state captured with `saveState()`.
    /// - Parameter advanceClock: move the calculator's real-time clock
    ///   forward by the wall-clock time elapsed since the capture.
    public func loadState(_ state: EmulatorState, advanceClock: Bool = true) throws {
        guard state.formatVersion == EmulatorState.currentFormatVersion else {
            throw EmulatorStateError.unsupportedFormat(state.formatVersion)
        }
        guard state.romSHA256 == rom.sha256 else {
            throw EmulatorStateError.romMismatch(expected: state.romSHA256, actual: rom.sha256)
        }
        guard state.memory.ram.count == ram.size, state.memory.flash.count == flash.size else {
            throw EmulatorStateError.corrupt("memory sizes do not match this calculator model")
        }

        releaseAllKeys()
        state.memory.ram.withUnsafeBytes { src in
            _ = UnsafeMutableRawBufferPointer(ram.storage).initializeMemory(as: UInt8.self, from: src.bindMemory(to: UInt8.self))
        }
        state.memory.flash.withUnsafeBytes { src in
            _ = UnsafeMutableRawBufferPointer(flash.storage).initializeMemory(as: UInt8.self, from: src.bindMemory(to: UInt8.self))
        }
        flash.isDirty = false

        cpu.state = state.cpu
        clock.restore(state.hardware.clock)
        scheduler.restore(state.hardware.schedulerDeadlines)
        flash.restore(state.memory.flashChip)
        mapper.restore(state.memory.mapper)
        interrupts.restore(state.hardware.interrupts)
        hardwareTimers.restore(state.hardware.hardwareTimerPeriod)
        crystalTimers.restore(state.hardware.crystalTimers)
        lcd.restore(state.hardware.lcd)
        keyboard.restore(state.hardware.keyboard)
        link.restore(state.hardware.link)
        asic.restore(state.hardware.asic)
        if !scheduler.isScheduled(.lcdFrame) {
            scheduler.schedule(.lcdFrame, after: EmulatorClock.ticksPerSecond / 60)
        }

        if advanceClock {
            let elapsed = Date().timeIntervalSince(state.savedAt)
            if elapsed > 0 && elapsed < Double(UInt32.max) {
                asic.advanceClock(bySeconds: UInt32(elapsed))
            }
        }
        frameBuilder.invalidate()
        onFrame?(frame)
    }
}

/// Binary (property list) encoding of save states.
public enum EmulatorStateCoder {
    public static func encode(_ state: EmulatorState) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(state)
    }

    public static func decode(_ data: Data) throws -> EmulatorState {
        do {
            return try PropertyListDecoder().decode(EmulatorState.self, from: data)
        } catch {
            throw EmulatorStateError.corrupt(error.localizedDescription)
        }
    }
}
