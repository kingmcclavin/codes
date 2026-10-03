import SwiftUI

/// Minimal controls: close, back, forward, reload — plus the current domain.
struct ViewerToolbar: View {
    @ObservedObject var browser: BrowserController
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ToolbarButton(systemImage: "xmark", label: "Close viewer", action: onClose)

            Divider().frame(height: 24).padding(.horizontal, 4)

            ToolbarButton(systemImage: "chevron.backward", label: "Back", action: browser.goBack)
                .disabled(!browser.canGoBack)
            ToolbarButton(systemImage: "chevron.forward", label: "Forward", action: browser.goForward)
                .disabled(!browser.canGoForward)

            if browser.isLoading {
                ToolbarButton(systemImage: "xmark.circle", label: "Stop loading", action: browser.stopLoading)
            } else {
                ToolbarButton(systemImage: "arrow.clockwise", label: "Reload", action: browser.reload)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(browser.displayHost)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Locked to \(browser.displayHost)")

        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(.bar)
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
