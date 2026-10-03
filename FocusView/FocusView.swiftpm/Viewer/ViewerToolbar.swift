import SwiftUI

/// Minimal controls: home, back, forward, reload, the current site, and the
/// ad-blocking shield.
struct ViewerToolbar: View {
    @ObservedObject var browser: BrowserController
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ToolbarButton(systemImage: "house", label: "Home", action: onClose)

            Divider().frame(height: 24).padding(.horizontal, 4)

            ToolbarButton(systemImage: "chevron.backward", label: "Back", action: browser.goBack)
                .disabled(!browser.canGoBack)
            ToolbarButton(systemImage: "chevron.forward", label: "Forward", action: browser.goForward)
                .disabled(!browser.canGoForward)

            if browser.isLoading {
                ToolbarButton(systemImage: "xmark", label: "Stop loading", action: browser.stopLoading)
            } else {
                ToolbarButton(systemImage: "arrow.clockwise", label: "Reload", action: browser.reload)
            }

            Spacer(minLength: 12)

            Text(browser.displayHost)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            ShieldButton(browser: browser)
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(.bar)
    }
}

/// Shows whether ad blocking is on and how many popups/redirects were
/// stopped. Tapping opens a small menu to turn blocking off for this site
/// if it ever breaks something.
private struct ShieldButton: View {
    @ObservedObject var browser: BrowserController

    private var isOn: Bool {
        browser.isAdBlockingEnabled && browser.isAdBlockingAvailable
    }

    var body: some View {
        Menu {
            if browser.isAdBlockingAvailable {
                Toggle(isOn: Binding(
                    get: { browser.isAdBlockingEnabled },
                    set: { browser.setAdBlocking($0) }
                )) {
                    Label("Block Ads", systemImage: "shield.lefthalf.filled")
                }
            } else {
                Text("Ad blocking is unavailable")
            }
            Text("Popups & redirects blocked: \(browser.blockedCount)")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "shield.lefthalf.filled" : "shield.slash")
                    .font(.system(size: 19, weight: .semibold))
                if browser.blockedCount > 0 {
                    Text("\(browser.blockedCount)")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                }
            }
            .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(isOn ? "Ad blocking on" : "Ad blocking off")
        .accessibilityValue("\(browser.blockedCount) blocked")
    }
}

private struct ToolbarButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .opacity(isEnabled ? 1 : 0.3)
        .accessibilityLabel(label)
    }
}
