import SwiftUI

struct OtherSurfacesSection: View {
    var body: some View {
        Section {
            NavigationLink("Native Instagram app & Safari") { NotInThisBuildView() }
        } header: {
            Text("Other ways to use Instagram")
        } footer: {
            Text("Reels are only filtered in the Instagram tab of this app.")
        }
    }
}

private struct NotInThisBuildView: View {
    var body: some View {
        Form {
            Section {
                Text("Reels can only be filtered when you open Instagram from Reels Guard.")
                Text("The Instagram app itself can't be filtered on iPhone or iPad. iOS doesn't allow any app to see inside another app.")
                    .foregroundStyle(.secondary)
            }
            Section("Not available in the Swift Playgrounds version") {
                Text("Safari extension: the same rules for instagram.com in Safari.")
                Text("Share extension: share a Reel from Instagram straight to Reels Guard. Here, copy the link and paste it into Shared with me instead.")
                Text("Screen Time lock for the Instagram app.")
            }
            Section {
                Text("These need app extensions and Apple entitlements, which require building the full project in Xcode on a Mac.")
                    .foregroundStyle(.secondary)
            }
            Section("Tip") {
                Text("To make the Instagram app less tempting, move it off your Home Screen or delete it, and use Reels Guard instead.")
            }
        }
        .navigationTitle("Not in This Version")
    }
}
