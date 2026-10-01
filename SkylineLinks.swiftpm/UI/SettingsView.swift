import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: GameStore
    let navigate: (AppScreen) -> Void
    @State private var confirmReset = false

    var body: some View {
        ZStack {
            UIStyle.background.ignoresSafeArea()
            VStack(spacing: 12) {
                ScreenHeader(title: "Settings", coins: store.progress.coins) { navigate(.menu) }
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 12) {
                            Toggle("Sound effects", isOn: $store.progress.soundOn)
                            Toggle("Haptics", isOn: $store.progress.hapticsOn)
                            Toggle("Show swing tutorial", isOn: $store.progress.showTutorial)
                            Toggle("3D view (turn off for classic top-down 2D)", isOn: $store.progress.use3D)
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .tint(UIStyle.accent)
                        .panel()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("HOW TO PLAY")
                                .font(.caption.weight(.heavy))
                                .foregroundColor(.white.opacity(0.6))
                            Text("1. Aim: in 3D drag left/right to turn and up/down for distance; in 2D drag the yellow target.")
                            Text("2. Pick a club from the strip at the bottom (the game suggests one).")
                            Text("3. Press and HOLD the swing button. Release when the power bar reaches the white line (100%).")
                            Text("4. Tap again when the needle crosses the green PERFECT zone.")
                            Text("5. Putts only need step 3. Read the slope arrows on the green.")
                            Text("Wind pushes the ball while it flies. The dotted preview ignores wind.")
                                .foregroundColor(UIStyle.gold)
                        }
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panel()

                        Button("Reset all progress") { confirmReset = true }
                            .buttonStyle(BigButtonStyle(color: UIStyle.danger, foreground: .white))
                    }
                    .padding()
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .alert("Reset progress?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { store.resetProgress() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Coins, cards, upgrades and unlocked courses will be erased.")
        }
    }
}
