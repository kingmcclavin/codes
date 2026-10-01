import SwiftUI

/// App-wide state: the saved player progress plus actions that change it.
final class GameStore: ObservableObject {
    @Published var progress: PlayerProgress {
        didSet {
            SaveManager.save(progress)
            syncSettings()
        }
    }

    private var rng = SeededRandom(seed: UInt64.random(in: 1...UInt64.max))

    init() {
        progress = SaveManager.load() ?? PlayerProgress.newPlayer()
        syncSettings()
    }

    private func syncSettings() {
        Feedback.shared.hapticsOn = progress.hapticsOn
        Feedback.shared.soundOn = progress.soundOn
    }

    func bag() -> [ClubType: EquippedClub] {
        progress.bag()
    }

    func buyPack(_ pack: PackType) -> [PackReveal]? {
        var p = progress
        let result = PackSystem.buy(pack, progress: &p, rng: &rng)
        if result != nil {
            progress = p
        }
        return result
    }

    func upgrade(_ cardID: String) -> Bool {
        var p = progress
        let ok = p.upgrade(cardID)
        if ok {
            progress = p
            Feedback.shared.play(.reveal)
            Feedback.shared.success()
        }
        return ok
    }

    func equip(_ cardID: String) {
        progress.equip(cardID)
        Feedback.shared.impact(.light)
    }

    func applyRound(_ result: RoundResult) -> RewardBreakdown {
        var p = progress
        let reward = RewardSystem.apply(result, to: &p)
        progress = p
        return reward
    }

    func dismissTutorial() {
        progress.showTutorial = false
    }

    func resetProgress() {
        SaveManager.reset()
        progress = PlayerProgress.newPlayer()
    }
}
