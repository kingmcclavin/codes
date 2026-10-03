import SwiftUI

/// Switches between the start page and the locked-down viewer.
struct RootView: View {
    @State private var openedURL: URL?

    var body: some View {
        Group {
            if let url = openedURL {
                ViewerView(url: url) {
                    openedURL = nil
                }
                // A new URL gets a brand-new viewer and web view.
                .id(url)
                .transition(.opacity)
            } else {
                StartView { url in
                    openedURL = url
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: openedURL)
    }
}
