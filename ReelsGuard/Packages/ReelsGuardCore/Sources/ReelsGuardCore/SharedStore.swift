import Foundation

public enum AppGroup {
    /// Must match the App Group in every target's entitlements (see project.yml).
    public static let identifier = "group.com.example.reelsguard"
}

/// A link the user explicitly shared into Reels Guard (share extension,
/// paste, or `reelsguard://open?url=`). Only the URL and the time are kept.
public struct SharedReel: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var url: URL
    public var receivedAt: Date

    public init(id: UUID = UUID(), url: URL, receivedAt: Date = Date()) {
        self.id = id
        self.url = url
        self.receivedAt = receivedAt
    }
}

/// Local-only persistence in the shared App Group container. Nothing here is
/// ever sent over the network.
public final class SharedStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()

    private enum Key {
        static let settings = "reelsGuard.settings.v1"
        static let budget = "reelsGuard.budget.v1"
        static let inbox = "reelsGuard.inbox.v1"
    }

    public static let inboxLimit = 50

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    // MARK: Settings

    public func loadSettings() -> GuardSettings { load(Key.settings) ?? GuardSettings() }
    public func saveSettings(_ settings: GuardSettings) { save(settings, Key.settings) }

    @discardableResult
    public func updateSettings(_ change: (inout GuardSettings) -> Void) -> GuardSettings {
        lock.lock(); defer { lock.unlock() }
        var settings = loadSettings()
        change(&settings)
        saveSettings(settings)
        return settings
    }

    // MARK: Reel time budget

    public func loadBudget() -> ReelTimeBudget { load(Key.budget) ?? ReelTimeBudget() }
    public func saveBudget(_ budget: ReelTimeBudget) { save(budget, Key.budget) }

    // MARK: Shared-with-me inbox

    public func loadInbox() -> [SharedReel] { load(Key.inbox) ?? [] }

    public func addToInbox(_ url: URL, now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        var inbox = loadInbox().filter { $0.url != url }
        inbox.insert(SharedReel(url: url, receivedAt: now), at: 0)
        save(Array(inbox.prefix(Self.inboxLimit)), Key.inbox)
    }

    public func removeFromInbox(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        save(loadInbox().filter { $0.id != id }, Key.inbox)
    }

    public func clearInbox() { defaults.removeObject(forKey: Key.inbox) }

    // MARK: Helpers

    private func load<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
