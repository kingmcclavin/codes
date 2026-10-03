import Combine
import Foundation
import UIKit
import WebKit

/// A short message shown in the blocked-navigation toast.
struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

/// Owns the single WKWebView used by the viewer, enforces `NavigationPolicy`
/// on every navigation, and publishes state for the SwiftUI controls.
///
/// SwiftUI never touches WebKit directly: views call the methods here and read
/// the @Published properties.
@MainActor
final class BrowserController: NSObject, ObservableObject {
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var pageTitle = ""
    @Published private(set) var currentURL: URL?
    @Published private(set) var loadError: String?
    @Published var toast: ToastMessage?

    let webView: WKWebView
    private let policy = NavigationPolicy()
    private let initialURL: URL
    private var hasLoadedInitialURL = false
    private var observers = Set<AnyCancellable>()

    init(initialURL: URL) {
        self.initialURL = initialURL
        self.webView = WKWebView(frame: .zero, configuration: Self.makeConfiguration())
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        // Link previews offer "Open in Safari"-style escapes; keep everything in-app.
        webView.allowsLinkPreview = false

        bindWebViewState()
    }

    private static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        // Video players need JavaScript, but scripts may not open windows on their own.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        // Play videos inside the page instead of forcing the system player.
        configuration.allowsInlineMediaPlayback = true
        return configuration
    }

    private func bindWebViewState() {
        webView.publisher(for: \.canGoBack).assign(to: &$canGoBack)
        webView.publisher(for: \.canGoForward).assign(to: &$canGoForward)
        webView.publisher(for: \.isLoading).assign(to: &$isLoading)
        webView.publisher(for: \.estimatedProgress).assign(to: &$progress)
        webView.publisher(for: \.url).assign(to: &$currentURL)
        webView.publisher(for: \.title)
            .map { $0 ?? "" }
            .assign(to: &$pageTitle)
    }

    // MARK: - Controls

    /// Loads the URL the viewer was opened with. Safe to call repeatedly.
    func loadInitialPageIfNeeded() {
        guard !hasLoadedInitialURL else { return }
        hasLoadedInitialURL = true
        webView.load(URLRequest(url: initialURL))
    }

    /// Steps back through this web view's own history only. With no history
    /// this does nothing, so the user stays on the current page.
    func goBack() {
        guard webView.canGoBack else { return }
        webView.goBack()
    }

    func goForward() {
        guard webView.canGoForward else { return }
        webView.goForward()
    }

    func reload() {
        loadError = nil
        if webView.url == nil {
            webView.load(URLRequest(url: initialURL))
        } else {
            webView.reload()
        }
    }

    func stopLoading() {
        webView.stopLoading()
    }

    /// The domain shown in the viewer's top bar.
    var displayHost: String {
        let host = (currentURL ?? initialURL).host ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func showToast(_ text: String) {
        toast = ToastMessage(text: text)
    }

    private func apply(_ decision: NavigationDecision) -> WKNavigationActionPolicy {
        switch decision {
        case .allow:
            return .allow
        case .loadInCurrentView(let url):
            webView.load(URLRequest(url: url))
            return .cancel
        case .block(let reason):
            showToast(reason.message)
            return .cancel
        }
    }

    private static func request(for action: WKNavigationAction) -> NavigationRequest {
        NavigationRequest(
            url: action.request.url,
            isMainFrame: action.targetFrame?.isMainFrame ?? true,
            opensNewWindow: action.targetFrame == nil,
            isUserInitiated: action.navigationType == .linkActivated
        )
    }

    private static func isBenignCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }
        // WebKitErrorFrameLoadInterruptedByPolicyChange: we cancelled it ourselves.
        if nsError.domain == WKError.errorDomain && nsError.code == 102 {
            return true
        }
        return false
    }
}

// MARK: - WKNavigationDelegate

extension BrowserController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let decision = policy.decide(Self.request(for: navigationAction))
        decisionHandler(apply(decision))
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        // Anything WebKit can't display would become a download; don't start one.
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            if navigationResponse.isForMainFrame {
                showToast("Download blocked")
            }
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadError = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        guard !Self.isBenignCancellation(error) else { return }
        loadError = error.localizedDescription
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !Self.isBenignCancellation(error) else { return }
        loadError = error.localizedDescription
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // The page's process crashed (often memory pressure during video). Recover in place.
        webView.reload()
    }
}

// MARK: - WKUIDelegate

extension BrowserController: WKUIDelegate {
    /// Called for target="_blank" links and window.open(). We never return a
    /// new web view, so no extra windows or tabs can exist.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        var request = Self.request(for: navigationAction)
        request.opensNewWindow = true
        _ = apply(policy.decide(request))
        return nil
    }

    /// Replaces the default long-press link menu (which can hand links to
    /// other apps) with a single in-app "Copy Link" action.
    func webView(
        _ webView: WKWebView,
        contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
        completionHandler: @escaping (UIContextMenuConfiguration?) -> Void
    ) {
        guard let linkURL = elementInfo.linkURL else {
            completionHandler(nil)
            return
        }
        let configuration = UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let copy = UIAction(title: "Copy Link", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.url = linkURL
            }
            return UIMenu(title: linkURL.host ?? "", children: [copy])
        }
        completionHandler(configuration)
    }
}
