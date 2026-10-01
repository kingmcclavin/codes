import SwiftUI

/// Main-screen links to the surfaces outside the in-app browser.
struct OtherSurfacesSection: View {
    var body: some View {
        Section("Other ways to use Instagram") {
            NavigationLink("Native Instagram app") { NativeAppLockView() }
            NavigationLink("Safari") { SafariSetupView() }
        }
    }
}
