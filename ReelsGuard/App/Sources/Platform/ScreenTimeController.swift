import FamilyControls
import ManagedSettings
import SwiftUI

extension ManagedSettingsStore.Name {
    static let reelsGuard = Self("reelsGuard")
}

/// Screen Time integration (FamilyControls + ManagedSettings).
///
/// What this can do on stock iOS: shield the *entire* native Instagram app,
/// so the user is nudged to use Instagram through Reels Guard's filtered
/// browser or Safari + the Reels Guard extension instead.
///
/// What it can't do: see anything inside Instagram. The app the user picks is
/// returned as an opaque `ApplicationToken`; Reels Guard never even learns
/// its name, let alone which Reel is on screen.
@MainActor
final class ScreenTimeController: ObservableObject {
    @Published private(set) var isAuthorized = false
    @Published private(set) var isLocked: Bool
    @Published var selection: FamilyActivitySelection {
        didSet {
            saveSelection()
            applyShield()
        }
    }

    private let store = ManagedSettingsStore(named: .reelsGuard)
    private let defaults = UserDefaults.standard
    private let selectionKey = "reelsGuard.screenTime.selection"
    private let lockedKey = "reelsGuard.screenTime.locked"

    init() {
        if let data = defaults.data(forKey: selectionKey),
           let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = saved
        } else {
            selection = FamilyActivitySelection()
        }
        isLocked = defaults.bool(forKey: lockedKey)
        refreshAuthorization()
    }

    var hasSelection: Bool { !selection.applicationTokens.isEmpty }

    func refreshAuthorization() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        applyShield()
    }

    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        refreshAuthorization()
    }

    func setLocked(_ locked: Bool) {
        isLocked = locked
        defaults.set(locked, forKey: lockedKey)
        applyShield()
    }

    private func applyShield() {
        guard isLocked, isAuthorized, hasSelection else {
            store.clearAllSettings()
            return
        }
        // Only the chosen apps are shielded. Categories and web domains are
        // ignored on purpose: shielding instagram.com would also block the
        // filtered web experience this lock is meant to push the user toward.
        store.shield.applications = selection.applicationTokens
    }

    private func saveSelection() {
        if let data = try? JSONEncoder().encode(selection) {
            defaults.set(data, forKey: selectionKey)
        }
    }
}
