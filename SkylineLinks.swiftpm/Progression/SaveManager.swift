import Foundation

/// Saves progress as JSON in UserDefaults. Works offline and inside Swift Playgrounds.
enum SaveManager {
    private static let key = "skylinelinks.progress.v1"

    static func load() -> PlayerProgress? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PlayerProgress.self, from: data)
    }

    static func save(_ progress: PlayerProgress) {
        if let data = try? JSONEncoder().encode(progress) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
