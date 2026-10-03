import Foundation

/// A WebKit-independent description of something the page is trying to do.
/// `BrowserController` translates WKNavigationAction into this so the policy
/// can be reasoned about (and later unit-tested) without a web view.
struct NavigationRequest: Equatable {
    /// Destination of the navigation. WebKit occasionally reports none.
    var url: URL?
    /// True when the top-level page would change (not an iframe/ad slot).
    var isMainFrame: Bool
    /// True when the page asked for a new tab/window (target="_blank",
    /// window.open, etc.).
    var opensNewWindow: Bool
    /// True when WebKit reports the navigation came from the user tapping a link.
    var isUserInitiated: Bool
}

enum NavigationDecision: Equatable {
    /// Let WebKit perform the navigation as requested.
    case allow
    /// Don't open anything new; load this URL in the existing web view instead.
    case loadInCurrentView(URL)
    /// Refuse the navigation and stay where we are.
    case block(BlockReason)
}

enum BlockReason: Equatable {
    case missingURL
    case unsupportedScheme(String)
    case popupWindow(host: String?)
    case topLevelDataURL

    /// Short, non-intrusive text for the blocked-navigation toast.
    var message: String {
        switch self {
        case .missingURL:
            return "Navigation blocked"
        case .unsupportedScheme(let scheme):
            return "Blocked link to another app (\(scheme):)"
        case .popupWindow(let host):
            if let host { return "Popup blocked: \(host)" }
            return "Popup blocked"
        case .topLevelDataURL:
            return "Navigation blocked"
        }
    }
}

/// Central decision point for every navigation the web view attempts.
///
/// Phase 1 rules:
/// - Only http/https may load as a top-level page. Anything else (tel:, mailto:,
///   itms-apps:, custom app schemes…) is blocked so the page can't hand the
///   user off to another app.
/// - Subframes may also use about:/blob:/data:, which embedded players rely on.
/// - New windows are never created. A user tap on a target="_blank" link is
///   loaded in the current view; script-initiated popups are blocked.
///
/// Phase 2 will add the trusted-domain allowlist on top of these rules.
struct NavigationPolicy {
    static let webSchemes: Set<String> = ["http", "https"]
    static let subframeOnlySchemes: Set<String> = ["about", "blob", "data"]

    func decide(_ request: NavigationRequest) -> NavigationDecision {
        guard let url = request.url, let scheme = url.scheme?.lowercased() else {
            return .block(.missingURL)
        }

        if request.opensNewWindow {
            return decideNewWindow(url: url, scheme: scheme, isUserInitiated: request.isUserInitiated)
        }

        if Self.webSchemes.contains(scheme) {
            return .allow
        }

        if request.isMainFrame {
            // The initial empty document is about:blank; let that through.
            if scheme == "about" { return .allow }
            if scheme == "data" { return .block(.topLevelDataURL) }
            return .block(.unsupportedScheme(scheme))
        }

        if Self.subframeOnlySchemes.contains(scheme) {
            return .allow
        }
        return .block(.unsupportedScheme(scheme))
    }

    private func decideNewWindow(url: URL, scheme: String, isUserInitiated: Bool) -> NavigationDecision {
        guard Self.webSchemes.contains(scheme) else {
            return .block(.unsupportedScheme(scheme))
        }
        guard isUserInitiated else {
            return .block(.popupWindow(host: url.host))
        }
        return .loadInCurrentView(url)
    }
}
