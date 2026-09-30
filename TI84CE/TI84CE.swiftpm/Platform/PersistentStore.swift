import Foundation
#if canImport(EmulatorCore)
import EmulatorCore
#endif

/// File-based persistence for calculator memory.
///
/// Everything lives under Application Support/TI84CE:
///
///     ROM/ti84ce.rom            imported ROM (see ROMLibrary)
///     State/autosave.ti84state  written whenever the app leaves the foreground,
///                               restored on launch: RAM, archive (flash), CPU and
///                               hardware state, so the calculator resumes exactly
///     State/slot-N.ti84state    manual "Save RAM" snapshots
///
/// Snapshots are binary property lists; flash is stored as a diff against the ROM.
public final class PersistentStore {
    public let root: URL

    public init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.root = support.appendingPathComponent("TI84CE", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        excludeFromBackupIfNeeded()
    }

    public var stateDirectory: URL { root.appendingPathComponent("State", isDirectory: true) }
    public var autosaveURL: URL { stateDirectory.appendingPathComponent("autosave.ti84state") }
    public func slotURL(_ slot: Int) -> URL { stateDirectory.appendingPathComponent("slot-\(slot).ti84state") }

    public var romLibrary: ROMLibrary { ROMLibrary(storageDirectory: root) }

    public func write(_ state: EmulatorState, to url: URL) throws {
        let data = try Emulator.encode(state)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public func read(from url: URL) throws -> EmulatorState {
        try Emulator.decode(Data(contentsOf: url))
    }

    public func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    public func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    public func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// The ROM copy is large and re-importable, so keep it out of device backups.
    private func excludeFromBackupIfNeeded() {
        var romDir = root.appendingPathComponent("ROM", isDirectory: true)
        try? FileManager.default.createDirectory(at: romDir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? romDir.setResourceValues(values)
    }
}
