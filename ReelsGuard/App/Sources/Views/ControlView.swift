import ReelsGuardCore
import SwiftUI

/// The Settings tab: "Instagram Reels Control".
struct ControlView: View {
    @EnvironmentObject private var model: SettingsModel
    @State private var confirmStrictOn = false
    @State private var showStrictOff = false

    private var strict: Bool { model.settings.strictMode }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Instagram Reels Control")
                            .font(.title2.weight(.bold))
                        Text("Watch what you intentionally choose. Stop Instagram from automatically feeding you more.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle("Reels from people I follow", isOn: model.binding(\.allowFollowedReels))
                        .disabled(strict)
                    Toggle("Reels sent to me", isOn: model.binding(\.allowSentReels))
                        .disabled(strict)
                    Toggle("Reels opened from profiles", isOn: model.binding(\.allowProfileReels))
                    LabeledContent("Recommended Reels", value: "BLOCKED")
                    LabeledContent("Infinite scrolling", value: "BLOCKED")
                } header: {
                    Text("Reels")
                } footer: {
                    Text(strict
                         ? "Strict Mode: only Reels from accounts you follow, and Reels sent to you. Profile Reels also need a follow. Explore is blocked."
                         : "After a Reel you chose, the next one plays only if it's from someone you follow.")
                }

                Section {
                    Toggle("Strict Mode", isOn: strictBinding)
                } footer: {
                    Text("Turning Strict Mode off takes a deliberate extra step.")
                }

                Section {
                    Picker("Reels limit", selection: limitBinding) {
                        ForEach(ReelLimit.allCases) { Text($0.label).tag($0) }
                    }
                    if model.settings.reelLimit != .off {
                        Picker("Cooldown", selection: cooldownBinding) {
                            ForEach(CooldownLength.allCases) { Text($0.label).tag($0) }
                        }
                        if let status = model.reelTimeStatus {
                            Text(status).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Reel time")
                } footer: {
                    Text(AppFeatures.hasSafariExtension
                         ? "Counts only time spent watching Reels in Reels Guard and Safari. The rest of Instagram isn't limited."
                         : "Counts only time spent watching Reels in Reels Guard. The rest of Instagram isn't limited.")
                }

                Section {
                    NavigationLink {
                        InboxView()
                    } label: {
                        LabeledContent("Shared with me", value: "\(model.inbox.count)")
                    }
                    NavigationLink("Accounts I follow") { FollowedAccountsView() }
                }

                OtherSurfacesSection()

                Section {
                    NavigationLink("What Reels Guard can and can't do") { LimitationsView() }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Turn on Strict Mode?", isPresented: $confirmStrictOn) {
            Button("Turn On") { model.update { $0.strictMode = true } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only Reels from accounts you follow and Reels sent to you will play. Explore is blocked. Turning it off later requires typing a confirmation and waiting.")
        }
        .sheet(isPresented: $showStrictOff) {
            StrictModeDisableView { model.update { $0.strictMode = false } }
        }
    }

    private var strictBinding: Binding<Bool> {
        Binding(
            get: { model.settings.strictMode },
            set: { on in if on { confirmStrictOn = true } else { showStrictOff = true } }
        )
    }

    private var limitBinding: Binding<ReelLimit> {
        Binding(get: { model.settings.reelLimit }, set: { value in model.update { $0.reelLimit = value } })
    }

    private var cooldownBinding: Binding<CooldownLength> {
        Binding(get: { model.settings.cooldown }, set: { value in model.update { $0.cooldown = value } })
    }
}
