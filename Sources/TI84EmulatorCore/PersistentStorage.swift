import Foundation

/// File-based persistence of calculator memory.
///
/// Layout (inside `directory`, one folder per ROM so different ROMs never
/// share memory):
///
///     <rom-sha256-prefix>/autosave.ti84state   full machine state (resume exactly)
///     <rom-sha256-prefix>/ram.bin              RAM image    (Save RAM / Load RAM)
///     <rom-sha256-prefix>/flash.bin            Flash image  (OS + archived variables)
///     <rom-sha256-prefix>/slot-<n>.ti84state   user save-state slots
///
/// The host app picks the directory (Application Support on iOS). Binary
/// memory images are stored as files rather than in UserDefaults.
public final class PersistentStorage {
    public let directory: URL
    private let fileManager = FileManager.default

    public init(directory: URL) {
        self.directory = directory
    }

    /// `<Application Support>/TI84Emulator`.
    public static func defaultDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return base.appendingPathComponent("TI84Emulator", isDirectory: true)
    }

    public func folder(for rom: ROMImage) throws -> URL {
        let url = directory.appendingPathComponent(String(rom.sha256.prefix(16)), isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Full state

    public func autosaveURL(for rom: ROMImage) throws -> URL {
        try folder(for: rom).appendingPathComponent("autosave.ti84state")
    }

    public func slotURL(_ slot: Int, for rom: ROMImage) throws -> URL {
        try folder(for: rom).appendingPathComponent("slot-\(slot).ti84state")
    }

    public func writeState(_ state: EmulatorState, to url: URL) throws {
        try EmulatorStateCoder.encode(state).write(to: url, options: .atomic)
    }

    public func readState(from url: URL) throws -> EmulatorState? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try EmulatorStateCoder.decode(Data(contentsOf: url))
    }

    /// Saves the whole machine so the next launch resumes where it left off.
    public func autosave(_ emulator: Emulator) throws {
        try writeState(emulator.saveState(), to: autosaveURL(for: emulator.rom))
        try saveFlashIfNeeded(emulator)
    }

    /// Restores the autosave if one exists. Returns false when there is none.
    @discardableResult
    public func restoreAutosave(into emulator: Emulator) throws -> Bool {
        guard let state = try readState(from: autosaveURL(for: emulator.rom)) else {
            // No full state: still bring back the archive if we have it.
            try loadFlash(into: emulator)
            return false
        }
        try emulator.loadState(state)
        return true
    }

    public func deleteAutosave(for rom: ROMImage) throws {
        let url = try autosaveURL(for: rom)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    // MARK: RAM

    public func saveRAM(_ emulator: Emulator) throws {
        try Data(emulator.ram.storage).write(to: folder(for: emulator.rom).appendingPathComponent("ram.bin"),
                                             options: .atomic)
    }

    /// Loads the saved RAM image and resets the CPU so the OS picks it up.
    @discardableResult
    public func loadRAM(into emulator: Emulator) throws -> Bool {
        let url = try folder(for: emulator.rom).appendingPathComponent("ram.bin")
        guard fileManager.fileExists(atPath: url.path) else { return false }
        let data = try Data(contentsOf: url)
        guard data.count == emulator.ram.size else {
            throw EmulatorStateError.corrupt("RAM image has the wrong size")
        }
        emulator.ram.load([UInt8](data))
        emulator.reset()
        return true
    }

    /// Clears RAM (the OS will report "RAM cleared") and removes saved RAM
    /// and autosave files. The Flash archive is kept.
    public func resetRAM(_ emulator: Emulator) throws {
        emulator.clearRAMAndReset()
        let folder = try folder(for: emulator.rom)
        for name in ["ram.bin", "autosave.ti84state"] {
            let url = folder.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        }
    }

    // MARK: Flash (archive)

    public func saveFlashIfNeeded(_ emulator: Emulator) throws {
        guard emulator.flash.isDirty else { return }
        try Data(emulator.flash.storage).write(to: folder(for: emulator.rom).appendingPathComponent("flash.bin"),
                                               options: .atomic)
        emulator.flash.isDirty = false
    }

    public func loadFlash(into emulator: Emulator) throws {
        let url = try folder(for: emulator.rom).appendingPathComponent("flash.bin")
        guard fileManager.fileExists(atPath: url.path) else { return }
        let data = try Data(contentsOf: url)
        guard data.count == emulator.flash.size else { return }
        emulator.flash.load([UInt8](data))
        emulator.flash.isDirty = false
    }

    /// Erases the archive and restores the Flash chip from the ROM image.
    public func resetFlash(_ emulator: Emulator) throws {
        emulator.restoreFactoryFlash()
        emulator.flash.isDirty = false
        let url = try folder(for: emulator.rom).appendingPathComponent("flash.bin")
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }
}
