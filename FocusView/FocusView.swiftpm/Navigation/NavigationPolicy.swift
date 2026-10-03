import Foundation

/// A WebKit-independent description of something the page is trying to do.
/// `BrowserController` translates WKNavigationAction into this so the policy
/// can be reasoned about without a web view.
struct NavigationRequest: Equatable {
    /// Destination of the navigation. WebKit occasionally reports none.
    var url: URL?
    /// The page currently shown, used to tell "same site" from "elsewhere".
    var currentPageURL: URL?
    /// True when the top-level page would change (not an iframe/ad slot).
    var isMainFrame: Bool
    /// True when the page asked for a new tab/window (target="_blank",
    /// window.open, etc.).
    var opensNewWindow: Bool
    /// True when the user caused this: tapping a link, submitting a form,
    /// Back/Forward/Reload, or opening a URL from the app itself (including
    /// the server redirects that follow).
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
    case popup(URL)
    case redirect(URL)
    case topLevelDataURL

    /// Short, non-intrusive text for the blocked-navigation toast.
    var message: String {
        switch self {
        case .missingURL, .topLevelDataURL:
            return "Navigation blocked"
        case .unsupportedScheme(let scheme):
            return "Blocked link to another app (\(scheme):)"
        case .popup(let url):
            return "Popup blocked" + Self.hostSuffix(url)
        case .redirect(let url):
            return "Redirect blocked" + Self.hostSuffix(url)
        }
    }

    /// A blocked popup or redirect may have been legitimate; the user can
    /// choose to open it anyway. Scheme blocks are never overridable.
    var overridableURL: URL? {
        switch self {
        case .popup(let url), .redirect(let url):
            return url
        default:
            return nil
        }
    }

    private static func hostSuffix(_ url: URL) -> String {
        guard let host = url.host else { return "" }
        return ": " + (host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)
    }
}

/// Central decision point for every navigation the web view attempts.
///
/// Rules:
/// - Only http/https may load as a top-level page. Anything else (tel:,
///   mailto:, itms-apps:, custom app schemes…) is blocked so the page can't
///   hand the user off to another app. Subframes may also use about:/blob:/
///   data:, which embedded players rely on.
/// - New windows are never created. Script popups (window.open, popunders)
///   are blocked. A tapped target="_blank" link opens in the current view if
///   it stays on the same site; links to other sites are treated as popups,
///   since invisible "click anywhere" ad overlays are built exactly that way.
/// - The page itself may not move the top-level view to a different site.
///   That is how ad redirects work. Navigation the user caused is allowed.
struct NavigationPolicy {
    static let webSchemes: Set<String> = ["http", "https"]
    static let subframeOnlySchemes: Set<String> = ["about", "blob", "data"]

    func decide(_ request: NavigationRequest) -> NavigationDecision {
        guard let url = request.url, let scheme = url.scheme?.lowercased() else {
            return .block(.missingURL)
        }

        if request.opensNewWindow {
            return decideNewWindow(url: url, scheme: scheme, request: request)
        }

        if Self.webSchemes.contains(scheme) {
            if request.isMainFrame && isScriptRedirectToOtherSite(url: url, request: request) {
                return .block(.redirect(url))
            }
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

    private func decideNewWindow(url: URL, scheme: String, request: NavigationRequest) -> NavigationDecision {
        guard Self.webSchemes.contains(scheme) else {
            return .block(.unsupportedScheme(scheme))
        }
        guard request.isUserInitiated else {
            return .block(.popup(url))
        }
        if request.currentPageURL != nil && !SiteIdentity.isSameSite(url, request.currentPageURL) {
            return .block(.popup(url))
        }
        return .loadInCurrentView(url)
    }

    private func isScriptRedirectToOtherSite(url: URL, request: NavigationRequest) -> Bool {
        guard !request.isUserInitiated, request.currentPageURL?.host != nil else { return false }
        return !SiteIdentity.isSameSite(url, request.currentPageURL)
    }
}
