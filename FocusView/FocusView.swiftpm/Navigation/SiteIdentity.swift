import Foundation

/// Groups hosts into "sites" so that www.example.com, cdn.example.com and
/// example.com count as the same place, while ads.other.net does not.
///
/// This is a small approximation of the Public Suffix List, good enough to tell
/// "same site" from "somewhere else" for redirect and popup decisions.
enum SiteIdentity {
    /// Second-level labels that act like part of the suffix under a country
    /// code, e.g. example.co.uk or example.com.au.
    private static let countrySecondLevels: Set<String> = [
        "co", "com", "net", "org", "gov", "edu", "ac", "or", "ne", "go"
    ]

    static func site(for host: String) -> String {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let labels = host.split(separator: ".").map(String.init)

        // IP addresses and single-label hosts are their own site.
        if labels.count <= 2 || labels.allSatisfy({ Int($0) != nil }) {
            return host
        }

        let tld = labels[labels.count - 1]
        let secondLevel = labels[labels.count - 2]
        let keep = (tld.count == 2 && countrySecondLevels.contains(secondLevel)) ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }

    static func site(for url: URL?) -> String? {
        guard let host = url?.host, !host.isEmpty else { return nil }
        return site(for: host)
    }

    static func isSameSite(_ a: URL?, _ b: URL?) -> Bool {
        guard let siteA = site(for: a), let siteB = site(for: b) else { return false }
        return siteA == siteB
    }
}
