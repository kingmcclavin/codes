import SwiftUI

struct SafariSetupView: View {
    var body: some View {
        Form {
            Section {
                Text("The Reels Guard Safari extension applies the same rules to instagram.com in Safari, using the same settings as this app.")
            }
            Section("Turn it on") {
                Label("Open Settings → Apps → Safari → Extensions", systemImage: "1.circle")
                Label("Tap Reels Guard and turn it on", systemImage: "2.circle")
                Label("Set instagram.com to Allow", systemImage: "3.circle")
            }
            Section {
                Text("The extension only runs on instagram.com. It reads page addresses and, on Reel pages, the creator's name and Follow button. It never reads messages and sends nothing off your device.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Safari")
    }
}
