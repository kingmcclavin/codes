import Combine
import Foundation
import UIKit
import WebKit

/// A short message shown in the blocked-popup/redirect toast.
struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    /// When set, the toast offers "Open" so the user can override a block.
    var overrideURL: URL?
}

/// Owns the single WKWebView, applies the ad-blocking rules, enforces
/// `NavigationPolicy` on every navigation, and publishes state for SwiftUI.
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
    @Published private(set) var isAdBlockingEnabled = true
    @Published private(set) var isAdBlockingAvailable = true
    /// Popups and redirects stopped since this browser opened.
    @Published private(set) var blockedCount = 0
    @Published var toast: ToastMessage?

    let webView: WKWebView
    private let policy = NavigationPolicy()
    private let initialURL: URL
    private var hasStarted = false
    private var adBlockRules: WKContentRuleList?
    /// True from a user action (link tap, typed URL, Back…) until that page
    /// commits, so the server redirects that follow it are not mistaken for
    /// ad redirects.
    private var userNavigationInProgress = false

    init(initialURL: URL) {
        self.initialURL = initialURL
        self.webView = WKWebView(frame: .zero, configuration: Self.makeConfiguration())
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        // Link previews offer ways to open links in other apps; keep everything here.
        webView.allowsLinkPreview = false

        bindWebViewState()
    }

    private static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        // Video players need JavaScript, but scripts may not open windows on their own.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        // Let pages play video inline instead of forcing the system player.
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

    /// Installs the ad-blocking rules, then loads the starting page. Rules go
    /// in first so ads on the very first page are blocked too. Safe to call
    /// repeatedly.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        adBlockRules = await ContentBlocker.shared.ruleList()
        isAdBlockingAvailable = (adBlockRules != nil)
        applyAdBlockingRules()

        loadAsUser(initialURL)
    }

    /// Turns ad blocking on or off for this browser and reloads the page so
    /// the change takes effect. Useful if blocking ever breaks a site.
    func setAdBlocking(_ enabled: Bool) {
        isAdBlockingEnabled = enabled
        applyAdBlockingRules()
        reload()
    }

    private func applyAdBlockingRules() {
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        if isAdBlockingEnabled, let adBlockRules {
            controller.add(adBlockRules)
        }
    }

    /// Steps back through this browser's own history only. With no history
    /// this does nothing.
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
            loadAsUser(initialURL)
        } else {
            webView.reload()
        }
    }

    func stopLoading() {
        webView.stopLoading()
    }

    /// Opens a popup or redirect the user chose to allow from the toast.
    func openBlocked(_ url: URL) {
        toast = nil
        loadAsUser(url)
    }

    /// The domain shown in the top bar.
    var displayHost: String {
        let host = (currentURL ?? initialURL).host ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func loadAsUser(_ url: URL) {
        userNavigationInProgress = true
        webView.load(URLRequest(url: url))
    }

    private func apply(_ decision: NavigationDecision) -> WKNavigationActionPolicy {
        switch decision {
        case .allow:
            return .allow
        case .loadInCurrentView(let url):
            loadAsUser(url)
            return .cancel
        case .block(let reason):
            blockedCount += 1
            toast = ToastMessage(text: reason.message, overrideURL: reason.overridableURL)
            return .cancel
        }
    }

    private func navigationRequest(for action: WKNavigationAction, opensNewWindow: Bool) -> NavigationRequest {
        let targetsMainFrame = action.targetFrame?.isMainFrame ?? true

        let userCaused: Bool
        switch action.navigationType {
        case .linkActivated, .formSubmitted, .formResubmitted, .backForward, .reload:
            userCaused = true
        default:
            userCaused = userNavigationInProgress && targetsMainFrame && !opensNewWindow
        }
        // A tap inside an embedded frame (typically an ad iframe) that tries to
        // replace the whole page or open a window is not trusted as a user choice.
        // WebKit can report no source frame for app-initiated loads despite the
        // non-optional type, so read it as optional.
        let sourceIsMainFrame = (action.sourceFrame as WKFrameInfo?)?.isMainFrame ?? true
        let fromEmbeddedFrame = !sourceIsMainFrame && (targetsMainFrame || opensNewWindow)

        return NavigationRequest(
            url: action.request.url,
            currentPageURL: webView.url,
            isMainFrame: targetsMainFrame,
            opensNewWindow: opensNewWindow,
            isUserInitiated: userCaused && !fromEmbeddedFrame
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
        let request = navigationRequest(for: navigationAction, opensNewWindow: navigationAction.targetFrame == nil)
        let decision = policy.decide(request)
        if decision == .allow && request.isMainFrame && request.isUserInitiated {
            userNavigationInProgress = true
        }
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
                toast = ToastMessage(text: "Download blocked")
            }
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadError = nil
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // The user's page has arrived; from here on, the page moving itself
        // to another site counts as a redirect.
        userNavigationInProgress = false
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        userNavigationInProgress = false
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
    /// new web view, so no extra windows, tabs or popunders can exist.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let request = navigationRequest(for: navigationAction, opensNewWindow: true)
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
