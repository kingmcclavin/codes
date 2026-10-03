import Foundation

/// Reads and writes the academic database as JSON in the app's
/// Application Support folder.
///
/// Safety rules:
/// - Every save is atomic, and the previous good file is kept as a backup.
/// - If the main file cannot be read, it is moved aside (never overwritten)
///   and the backup is tried, so a bad file can't destroy a semester of data.
struct DatabaseFileStore {
    enum LoadOutcome: Equatable {
        /// No saved data yet (first launch).
        case empty
        case loaded
        /// The main file was unreadable; data came from the backup.
        case recoveredFromBackup(quarantinedFile: String)
        /// Neither file was readable. The unreadable file was kept for recovery.
        case failed(quarantinedFile: String?)
    }

    let directory: URL

    var databaseURL: URL { directory.appendingPathComponent("StudyOS-Data.json") }
    var backupURL: URL { directory.appendingPathComponent("StudyOS-Data.backup.json") }

    init(directory: URL) {
        self.directory = directory
    }

    /// The standard location on device.
    static func standard() -> DatabaseFileStore {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return DatabaseFileStore(directory: base.appendingPathComponent("StudyOS", isDirectory: true))
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISODates.string(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = ISODates.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(text)")
            }
            return date
        }
        return decoder
    }

    func load() -> (AcademicDatabase, LoadOutcome) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: databaseURL.path) else {
            if let backup = try? read(backupURL) {
                return (backup, .recoveredFromBackup(quarantinedFile: ""))
            }
            return (AcademicDatabase(), .empty)
        }
        do {
            return (try read(databaseURL), .loaded)
        } catch {
            let quarantined = quarantineMainFile()
            if let backup = try? read(backupURL) {
                return (backup, .recoveredFromBackup(quarantinedFile: quarantined ?? ""))
            }
            return (AcademicDatabase(), .failed(quarantinedFile: quarantined))
        }
    }

    func save(_ database: AcademicDatabase) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.makeEncoder().encode(database)
        // Keep the last good file as a backup before replacing it.
        if fm.fileExists(atPath: databaseURL.path), (try? read(databaseURL)) != nil {
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: databaseURL, to: backupURL)
        }
        try data.write(to: databaseURL, options: .atomic)
    }

    /// Writes a copy of the data for the user to share or keep.
    func exportCopy(_ database: AcademicDatabase, to url: URL) throws {
        try Self.makeEncoder().encode(database).write(to: url, options: .atomic)
    }

    func decodeImported(_ data: Data) throws -> AcademicDatabase {
        try Self.makeDecoder().decode(AcademicDatabase.self, from: data)
    }

    private func read(_ url: URL) throws -> AcademicDatabase {
        try Self.makeDecoder().decode(AcademicDatabase.self, from: Data(contentsOf: url))
    }

    /// Moves an unreadable data file aside so the next save can't overwrite it.
    private func quarantineMainFile() -> String? {
        let stamp = Int(Date().timeIntervalSince1970)
        let name = "StudyOS-Data.unreadable-\(stamp).json"
        let destination = directory.appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: databaseURL, to: destination)
            return name
        } catch {
            return nil
        }
    }
}

/// ISO-8601 dates ("2026-10-16T18:00:00.000Z"): readable in any tool, and
/// precise to the millisecond. Plain ISO-8601 without fractions is accepted too.
enum ISODates {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()
    private static let lock = NSLock()

    static func string(from date: Date) -> String {
        lock.lock(); defer { lock.unlock() }
        return fractional.string(from: date)
    }

    static func date(from text: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        return fractional.date(from: text) ?? plain.date(from: text)
    }
}
