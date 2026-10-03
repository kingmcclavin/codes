import SwiftUI

/// The browser screen: a slim control bar above a single ad-blocked web view.
struct ViewerView: View {
    let onClose: () -> Void

    @StateObject private var browser: BrowserController

    init(url: URL, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _browser = StateObject(wrappedValue: BrowserController(initialURL: url))
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewerToolbar(browser: browser, onClose: onClose)
            LoadingBar(progress: browser.progress, isLoading: browser.isLoading)

            WebViewContainer(controller: browser)
                .ignoresSafeArea(.container, edges: .bottom)
                .overlay(alignment: .top) {
                    if let message = browser.loadError {
                        LoadErrorBanner(message: message, onRetry: browser.reload)
                            .padding(16)
                    }
                }
        }
        .overlay(alignment: .bottom) {
            if let toast = browser.toast {
                BlockedToast(text: toast.text, onOpen: openAction(for: toast))
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: browser.toast)
        .task(id: browser.toast) {
            guard let toast = browser.toast else { return }
            // Leave a little longer to tap "Open" when the toast offers it.
            let seconds: UInt64 = toast.overrideURL == nil ? 2 : 4
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            if !Task.isCancelled {
                browser.toast = nil
            }
        }
        .task { await browser.start() }
        .background(Color(uiColor: .systemBackground))
    }

    private func openAction(for toast: ToastMessage) -> (() -> Void)? {
        guard let url = toast.overrideURL else { return nil }
        return { browser.openBlocked(url) }
    }
}

/// Thin progress line under the control bar.
private struct LoadingBar: View {
    let progress: Double
    let isLoading: Bool

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: proxy.size.width * progress)
                .opacity(isLoading ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: progress)
                .animation(.easeOut(duration: 0.4), value: isLoading)
        }
        .frame(height: 2)
    }
}

private struct LoadErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(maxWidth: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
