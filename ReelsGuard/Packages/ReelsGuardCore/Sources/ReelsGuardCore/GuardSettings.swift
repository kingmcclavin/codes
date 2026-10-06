import Foundation

public enum ReelLimit: Int, Codable, CaseIterable, Identifiable, Sendable {
    case off = 0
    case five = 5
    case ten = 10
    case fifteen = 15
    case thirty = 30

    public var id: Int { rawValue }
    public var seconds: TimeInterval? { self == .off ? nil : TimeInterval(rawValue * 60) }
    public var label: String { self == .off ? "Off" : "\(rawValue) minutes" }
}

public enum CooldownLength: Int, Codable, CaseIterable, Identifiable, Sendable {
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case fourHours = 240

    public var id: Int { rawValue }
    public var seconds: TimeInterval { TimeInterval(rawValue * 60) }
    public var label: String {
        switch self {
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .fourHours: return "4 hours"
        }
    }
}

/// User configuration. Stored as JSON in the shared App Group so the app and
/// the Safari extension see the same values.
///
/// Every field decodes with a default so older stored data keeps working as
/// fields are added.
public struct GuardSettings: Codable, Equatable, Sendable {
    public var allowFollowedReels = true
    public var allowSentReels = true
    public var allowProfileReels = true
    public var strictMode = false
    public var reelLimit: ReelLimit = .off
    public var cooldown: CooldownLength = .oneHour
    /// Use on-page signals (Follow / Following buttons) to decide follow status.
    public var usePageHints = true
    /// Remember accounts shown as "Following" when the user visits their profile.
    public var learnFollowsFromProfiles = true
    /// Accounts the user added by hand. Lower-cased usernames.
    public var manualFollows: [String] = []
    /// Accounts learned from profile visits. Lower-cased usernames.
    public var learnedFollows: [String] = []

    public init() {}

    public var knownFollows: Set<String> {
        Set(manualFollows).union(learnedFollows)
    }

    private enum CodingKeys: String, CodingKey {
        case allowFollowedReels, allowSentReels, allowProfileReels, strictMode, reelLimit, cooldown
        case usePageHints, learnFollowsFromProfiles, manualFollows, learnedFollows
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GuardSettings()
        allowFollowedReels = try c.decodeIfPresent(Bool.self, forKey: .allowFollowedReels) ?? d.allowFollowedReels
        allowSentReels = try c.decodeIfPresent(Bool.self, forKey: .allowSentReels) ?? d.allowSentReels
        allowProfileReels = try c.decodeIfPresent(Bool.self, forKey: .allowProfileReels) ?? d.allowProfileReels
        strictMode = try c.decodeIfPresent(Bool.self, forKey: .strictMode) ?? d.strictMode
        reelLimit = (try? c.decodeIfPresent(ReelLimit.self, forKey: .reelLimit)) ?? d.reelLimit
        cooldown = (try? c.decodeIfPresent(CooldownLength.self, forKey: .cooldown)) ?? d.cooldown
        usePageHints = try c.decodeIfPresent(Bool.self, forKey: .usePageHints) ?? d.usePageHints
        learnFollowsFromProfiles = try c.decodeIfPresent(Bool.self, forKey: .learnFollowsFromProfiles) ?? d.learnFollowsFromProfiles
        manualFollows = try c.decodeIfPresent([String].self, forKey: .manualFollows) ?? d.manualFollows
        learnedFollows = try c.decodeIfPresent([String].self, forKey: .learnedFollows) ?? d.learnedFollows
    }
}

/// The rules actually applied, after Strict Mode overrides.
public struct EffectivePolicy: Equatable, Sendable {
    public var allowFollowed: Bool
    public var allowSent: Bool
    public var allowProfile: Bool
    public var strict: Bool
    public var blockExplorePage: Bool
    public var reelLimit: TimeInterval?
    public var cooldown: TimeInterval

    public init(_ s: GuardSettings) {
        strict = s.strictMode
        reelLimit = s.reelLimit.seconds
        cooldown = s.cooldown.seconds
        if s.strictMode {
            // Strict Mode: only followed accounts, plus Reels sent to the user.
            allowFollowed = true
            allowSent = true
            allowProfile = s.allowProfileReels
            blockExplorePage = true
        } else {
            allowFollowed = s.allowFollowedReels
            allowSent = s.allowSentReels
            allowProfile = s.allowProfileReels
            blockExplorePage = false
        }
    }
}
