import Foundation

/// Turns whatever the user typed or pasted into a loadable web URL.
enum URLInputParser {
    /// Returns an http(s) URL, or nil if the text isn't a usable web address.
    /// "example.com/watch?v=1" becomes "https://example.com/watch?v=1".
    static func url(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }

        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard
            let components = URLComponents(string: candidate),
            let scheme = components.scheme?.lowercased(),
            NavigationPolicy.webSchemes.contains(scheme),
            let host = components.host, !host.isEmpty
        else { return nil }

        // Reject single words like "hello" that aren't real hosts.
        guard host.contains(".") || host == "localhost" else { return nil }

        return components.url
    }
}
