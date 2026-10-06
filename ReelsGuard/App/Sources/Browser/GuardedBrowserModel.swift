import ReelsGuardCore
import UIKit
import WebKit

/// Hosts instagram.com in a WKWebView and enforces the Reels policy.
///
/// This is the most capable enforcement surface available on stock iOS:
/// because Reels Guard owns the web view, it can observe page URLs and the
/// page DOM (through a script in an isolated content world), pause media and
/// cover the page with a blocking screen. None of this is possible for the
/// native Instagram app.
///
/// Privacy: the user signs in on instagram.com itself; the observer script
/// never reads form fields, and cookies stay in this app's own website data
/// store. Nothing is sent anywhere except Instagram's own servers.
@MainActor
final class GuardedBrowserModel: NSObject, ObservableObject {
    @Published private(set) var blockCopy: BlockScreenCopy?

    let webView: WKWebView
    private let service: ReelsGuardService
    private var state = GuardState()

    static let home = URL(string: "https://www.instagram.com/")!
    private static let world = WKContentWorld.world(name: "ReelsGuard")
    private static let handlerName = "reelsGuard"

    /// - Parameter startURL: a shared Reel to open, or `nil` for the home feed.
    ///   Starting with an empty `GuardState` makes the first Reel count as a
    ///   shared link (an intentional entry).
    init(service: ReelsGuardService, startURL: URL?) {
        self.service = service

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Present as mobile Safari so instagram.com serves its normal mobile site.
        configuration.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.observerSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: Self.world
        ))
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true

        super.init()

        configuration.userContentController.addScriptMessageHandler(
            WeakScriptMessageHandler(self), contentWorld: Self.world, name: Self.handlerName
        )
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: startURL ?? Self.home))
    }

    // MARK: Actions

    /// The only way out of the blocking screen: back to the home feed, with the
    /// Reel chain reset. There is intentionally no "next Reel" option.
    func backToInstagram() {
        state = GuardState()
        show(.allow)
        webView.load(URLRequest(url: Self.home))
    }

    /// Opens a Reel from "Shared with me". The fresh state makes it count as
    /// a shared link, i.e. an intentional entry.
    func openShared(_ url: URL) {
        state = GuardState()
        show(.allow)
        webView.load(URLRequest(url: url))
    }

    // MARK: Policy

    fileprivate func handle(_ body: Any) -> [String: Any] {
        guard let request = ReelsGuardService.decodeRequest(body) else {
            return ReelsGuardService.dictionary(.allow)
        }
        let result = service.handle(request, state: state)
        state = result.state
        show(result.decision)
        return ReelsGuardService.dictionary(ReelsGuardService.response(for: result.decision))
    }

    private func show(_ decision: GuardDecision) {
        switch decision {
        case .allow:
            if blockCopy != nil {
                blockCopy = nil
                webView.setAllMediaPlaybackSuspended(false, completionHandler: nil)
            }
        case let .block(reason):
            blockCopy = BlockScreenCopy(reason: reason)
            webView.pauseAllMediaPlayback(completionHandler: nil)
            webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        }
    }

    // MARK: Script

    private static let observerSource = ObserverScript.source + """

        ReelsGuardObserver.start({
          send: function (message) {
            return window.webkit.messageHandlers.\(GuardedBrowserModel.handlerName).postMessage(message);
          }
        });
        """

    private static func isInstagramOrLogin(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "l.instagram.com" { return false } // Instagram's outbound-link redirector
        return host == "instagram.com" || host.hasSuffix(".instagram.com")
            || host == "facebook.com" || host.hasSuffix(".facebook.com")
    }
}

// MARK: - WKNavigationDelegate

extension GuardedBrowserModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        guard navigationAction.targetFrame?.isMainFrame ?? true else { return .allow }
        let scheme = url.scheme?.lowercased() ?? ""
        if ["about", "blob", "data"].contains(scheme) { return .allow }
        guard scheme == "http" || scheme == "https" else { return .cancel }

        if Self.isInstagramOrLogin(url) {
            // Full page loads of the Reels feed are stopped before they render.
            // In-page (pushState) navigations are caught by the observer script.
            if InstagramURLClassifier.classify(url) == .reelsFeed {
                _ = handle(["type": "page", "url": url.absoluteString])
                return .cancel
            }
            return .allow
        }

        // Links that leave Instagram open in the user's browser, outside the guard.
        if navigationAction.navigationType == .linkActivated || url.host?.lowercased() == "l.instagram.com" {
            _ = await UIApplication.shared.open(url)
            return .cancel
        }
        return .allow // redirects during login / challenges
    }
}

// MARK: - WKUIDelegate

extension GuardedBrowserModel: WKUIDelegate {
    /// `target="_blank"` links open in the same guarded web view.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
}

// MARK: - Script messages

/// Breaks the retain cycle WKUserContentController → handler → web view.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    private weak var target: GuardedBrowserModel?

    init(_ target: GuardedBrowserModel) {
        self.target = target
    }

    @MainActor
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let target else { return (["decision": "allow"], nil) }
        return (target.handle(message.body), nil)
    }
}
