import Foundation

/// Reads/writes the app library (the list of `ContainerApp`s + folders) as a
/// single JSON document. Everything is local; nothing is ever uploaded.
struct LibrarySnapshot: Codable {
    var apps: [ContainerApp]
    var folders: [HomeFolder]
    var recentBundleIDs: [String]   // most-recent-first, for "Recently used"
    var hasAcknowledgedSafety: Bool

    static let empty = LibrarySnapshot(apps: [], folders: [],
                                       recentBundleIDs: [], hasAcknowledgedSafety: false)
}

final class PersistenceManager {
    static let shared = PersistenceManager()
    private let storage = ContainerStorage.shared
    private let queue = DispatchQueue(label: "dev.local.testapps.persistence")

    private init() {}

    func load() -> LibrarySnapshot {
        queue.sync {
            guard let data = try? Data(contentsOf: storage.libraryFileURL) else {
                return .empty
            }
            do {
                return try JSONDecoder().decode(LibrarySnapshot.self, from: data)
            } catch {
                DiagnosticLogger.shared.log(.fileSystem,
                    "Failed to decode library.json: \(error.localizedDescription). Starting empty.")
                return .empty
            }
        }
    }

    func save(_ snapshot: LibrarySnapshot) {
        queue.sync {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                try data.write(to: storage.libraryFileURL, options: .atomic)
            } catch {
                DiagnosticLogger.shared.log(.fileSystem,
                    "Failed to save library.json: \(error.localizedDescription)")
            }
        }
    }
}
