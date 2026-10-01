import Foundation

/// Extracts an Instagram Reel/post link from text shared by another app.
/// Instagram's share sheet sometimes passes a URL, sometimes text containing one.
public enum ReelLinkParser {
    public static func instagramURL(in text: String) -> URL? {
        let tokens = text.split(whereSeparator: { $0.isWhitespace || $0 == "\"" || $0 == "<" || $0 == ">" })
        for token in tokens where token.contains("instagram.com") {
            var candidate = String(token)
            if !candidate.lowercased().hasPrefix("http") { candidate = "https://" + candidate }
            if let url = URL(string: candidate), let normalized = normalize(url) { return normalized }
        }
        return nil
    }

    /// Accepts only instagram.com Reel / post links and strips tracking query items.
    public static func normalize(_ url: URL) -> URL? {
        guard InstagramURLClassifier.isInstagram(url) else { return nil }
        switch InstagramURLClassifier.classify(url) {
        case .reel, .post:
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = "https"
            components?.host = "www.instagram.com"
            components?.query = nil
            components?.fragment = nil
            return components?.url
        default:
            return nil
        }
    }
}
