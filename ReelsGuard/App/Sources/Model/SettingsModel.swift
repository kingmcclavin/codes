import ReelsGuardCore
import SwiftUI

/// UI-facing wrapper around the shared App Group store.
@MainActor
final class SettingsModel: ObservableObject {
    @Published private(set) var settings: GuardSettings
    @Published private(set) var budget: ReelTimeBudget
    @Published private(set) var inbox: [SharedReel]
    /// A shared Reel waiting to be opened in the Instagram tab.
    @Published var pendingOpen: URL?

    let store: SharedStore
    let service: ReelsGuardService

    init(store: SharedStore = SharedStore()) {
        self.store = store
        self.service = ReelsGuardService(store: store)
        settings = store.loadSettings()
        budget = store.loadBudget()
        inbox = store.loadInbox()
    }

    /// Picks up changes made by the Safari extension or share extension.
    func reload() {
        settings = store.loadSettings()
        budget = store.loadBudget()
        inbox = store.loadInbox()
    }

    func update(_ change: (inout GuardSettings) -> Void) {
        settings = store.updateSettings(change)
    }

    func binding(_ keyPath: WritableKeyPath<GuardSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { value in self.update { $0[keyPath: keyPath] = value } }
        )
    }

    var reelTimeStatus: String? {
        guard let limit = settings.reelLimit.seconds else { return nil }
        let now = Date()
        var current = budget
        current.normalize(now: now)
        if let until = current.activeCooldown(now: now) {
            return "Reels paused until \(until.formatted(date: .omitted, time: .shortened))"
        }
        let minutes = Int((current.remaining(limit: limit) / 60).rounded(.up))
        return "\(minutes) min of Reels left"
    }

    // MARK: Shared with me

    /// Opens a shared Reel in the Instagram tab.
    func open(_ url: URL) {
        pendingOpen = url
    }

    /// Adds a pasted link. Returns false if it isn't an Instagram Reel/post link.
    @discardableResult
    func addSharedLink(_ text: String) -> Bool {
        guard let url = ReelLinkParser.instagramURL(in: text) else { return false }
        store.addToInbox(url)
        inbox = store.loadInbox()
        return true
    }

    func removeShared(at offsets: IndexSet) {
        for index in offsets { store.removeFromInbox(inbox[index].id) }
        inbox = store.loadInbox()
    }

    /// `reelsguard://open?url=<instagram reel link>` — usable from Shortcuts.
    func handleOpenURL(_ url: URL) {
        guard url.scheme == "reelsguard",
              let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "url" })?.value,
              let reel = ReelLinkParser.instagramURL(in: link) else { return }
        store.addToInbox(reel)
        inbox = store.loadInbox()
        open(reel)
    }

    // MARK: Follow list

    func addManualFollow(_ username: String) {
        let name = username.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        guard InstagramURLClassifier.isUsername(name) else { return }
        update { settings in
            if !settings.manualFollows.contains(name) {
                settings.manualFollows.append(name)
                settings.manualFollows.sort()
            }
        }
    }

    func removeManualFollows(at offsets: IndexSet) {
        update { $0.manualFollows.remove(atOffsets: offsets) }
    }

    func removeLearnedFollows(at offsets: IndexSet) {
        update { $0.learnedFollows.remove(atOffsets: offsets) }
    }
}
