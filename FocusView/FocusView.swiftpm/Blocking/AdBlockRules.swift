import Foundation

/// The built-in ad blocking rules, written as a WebKit content rule list
/// (the same format Safari content blockers use). Kept free of WebKit so the
/// list is easy to read and extend.
///
/// The domain list targets ad networks, popunder/redirect networks and
/// trackers that show up on streaming sites. It deliberately leaves out video
/// CDNs and player providers so playback keeps working.
enum AdBlockRules {
    /// Bump when the rules change so WebKit recompiles them.
    static let identifier = "FocusView.AdBlock.v1"

    static let blockedDomains: [String] = [
        // Display and video ad networks
        "doubleclick.net",
        "googlesyndication.com",
        "googleadservices.com",
        "adservice.google.com",
        "amazon-adsystem.com",
        "adnxs.com",
        "rubiconproject.com",
        "pubmatic.com",
        "openx.net",
        "criteo.com",
        "criteo.net",
        "casalemedia.com",
        "advertising.com",
        "smartadserver.com",
        "spotxchange.com",
        "springserve.com",
        "teads.tv",
        "media.net",
        "yieldmo.com",
        "sharethrough.com",
        "33across.com",
        "taboola.com",
        "outbrain.com",
        "mgid.com",
        "revcontent.com",
        "adskeeper.com",
        // Popunder, push-ad and redirect networks
        "popads.net",
        "popcash.net",
        "propellerads.com",
        "onclickads.net",
        "onclkds.com",
        "adsterra.com",
        "adsterratech.com",
        "exoclick.com",
        "exosrv.com",
        "juicyads.com",
        "trafficjunky.net",
        "trafficstars.com",
        "hilltopads.net",
        "hilltopads.com",
        "clickadu.com",
        "adcash.com",
        "a-ads.com",
        "ad-maven.com",
        "admaven.com",
        "monetag.com",
        "zeropark.com",
        "bidvertiser.com",
        "richads.com",
        "pushground.com",
        "evadav.com",
        "galaksion.com",
        "adspyglass.com",
        "realsrv.com",
        "clickaine.com",
        // Trackers
        "google-analytics.com",
        "googletagservices.com",
        "scorecardresearch.com",
        "quantserve.com",
        "hotjar.com",
        "moatads.com",
        "adsafeprotected.com",
        "doubleverify.com",
    ]

    /// Element selectors for common ad slots and overlays. These are kept
    /// conservative: hiding something the video player needs would break it.
    static let hiddenSelectors: [String] = [
        ".adsbygoogle",
        "ins.adsbygoogle",
        "[id^='google_ads_']",
        "[id^='div-gpt-ad']",
        "iframe[src*='doubleclick.net']",
        "iframe[src*='googlesyndication.com']",
        "iframe[src*='amazon-adsystem.com']",
        "iframe[src*='exoclick']",
        "iframe[src*='adsterra']",
        "iframe[src*='popads']",
        "iframe[id^='google_ads_iframe']",
        "[class^='ad-container']",
        "[class^='ad-banner']",
        "[class^='ad-slot']",
        "[id^='ad-container']",
        "[id^='ad-banner']",
        "[id^='ad-slot']",
        ".ad-overlay",
        ".banner-ad",
        ".sponsored-ad",
        "[data-ad-slot]",
        "[data-ad-unit]",
        "[aria-label='Advertisement']",
        "a[href*='doubleclick.net']",
        "a[href*='/aff_c?']",
    ]

    /// The rule list as JSON, ready for WKContentRuleListStore.
    static func json() -> String {
        var rules: [[String: Any]] = blockedDomains.map { domain in
            [
                "trigger": ["url-filter": urlFilter(forDomain: domain)],
                "action": ["type": "block"],
            ]
        }
        rules.append([
            "trigger": ["url-filter": ".*"],
            "action": [
                "type": "css-display-none",
                "selector": hiddenSelectors.joined(separator: ", "),
            ],
        ])

        guard
            let data = try? JSONSerialization.data(withJSONObject: rules, options: []),
            let text = String(data: data, encoding: .utf8)
        else { return "[]" }
        return text
    }

    /// Matches the domain and any of its subdomains, e.g.
    /// "^https?://([a-z0-9.-]+\.)?doubleclick\.net[/:]". WebKit's rule
    /// regexes are limited (no alternation), so this sticks to simple syntax.
    static func urlFilter(forDomain domain: String) -> String {
        let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
        return "^https?://([a-z0-9.-]+\\.)?" + escaped + "[/:]"
    }
}
