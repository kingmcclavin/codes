import Foundation

/// The result of statically inspecting an IPA before attempting to launch it.
struct CompatibilityReport: Codable, Hashable {
    enum Level: String, Codable {
        case good = "GOOD"
        case limited = "LIMITED"
        case unsupported = "UNSUPPORTED"

        var symbolName: String {
            switch self {
            case .good: return "checkmark.seal.fill"
            case .limited: return "exclamationmark.triangle.fill"
            case .unsupported: return "xmark.octagon.fill"
            }
        }
    }

    struct Check: Codable, Hashable, Identifiable {
        enum Status: String, Codable {
            case pass, warn, fail, info
            var symbol: String {
                switch self {
                case .pass: return "checkmark"
                case .warn: return "exclamationmark.triangle"
                case .fail: return "xmark"
                case .info: return "info.circle"
                }
            }
        }
        var id: String { title }
        var status: Status
        var title: String
        var detail: String?
    }

    var level: Level
    var checks: [Check]

    /// The honest headline: whether the *current runtime* can actually launch
    /// this app. Distinct from static compatibility — an app can pass every
    /// static check and still not be runnable by a sandboxed container.
    var runtimeLaunchable: Bool
    var runtimeExplanation: String

    var summaryLine: String {
        switch level {
        case .good: return "Compatibility: GOOD"
        case .limited: return "Compatibility: LIMITED"
        case .unsupported: return "Compatibility: UNSUPPORTED"
        }
    }
}
