import Foundation

/// Decides whether the user follows a Reel's creator, using only data that is
/// already on the device: the user's own list of known follows and the hint
/// from the page they are looking at. Nothing is fetched from Instagram.
///
/// It errs toward "unknown": a missing Follow button is not proof of a follow,
/// and an unknown creator never extends a Reel chain.
public struct FollowResolver: Sendable {
    public var knownFollows: Set<String>
    public var usePageHints: Bool

    public init(knownFollows: Set<String>, usePageHints: Bool) {
        self.knownFollows = knownFollows
        self.usePageHints = usePageHints
    }

    public init(settings: GuardSettings) {
        self.init(knownFollows: settings.knownFollows, usePageHints: settings.usePageHints)
    }

    public func resolve(creator: String?, hint: FollowHint) -> FollowState {
        if let creator, knownFollows.contains(creator.lowercased()) { return .following }
        guard usePageHints else { return .unknown }
        switch hint {
        case .following: return .following
        case .notFollowing: return .notFollowing
        case .noFollowButton, .unknown: return .unknown
        }
    }
}
