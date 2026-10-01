import XCTest
@testable import ReelsGuardCore

final class ReelsGuardEngineTests: XCTestCase {
    private let engine = ReelsGuardEngine()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Drives the engine through a sequence of events, carrying state along.
    private struct Session {
        var state = GuardState()
        var budget = ReelTimeBudget()
        var settings = GuardSettings()
    }

    @discardableResult
    private func send(_ event: GuardEvent, _ s: inout Session, at time: Date? = nil) -> GuardDecision {
        let outcome = engine.process(event, state: s.state, settings: s.settings, budget: s.budget, now: time ?? now, calendar: calendar)
        s.state = outcome.state
        s.budget = outcome.budget
        return outcome.decision
    }

    private func page(_ url: String) -> GuardEvent { .page(InstagramURLClassifier.classify(url)) }
    private func reel(_ id: String, by creator: String?, _ hint: FollowHint = .unknown) -> GuardEvent {
        .reel(ReelSighting(reelID: id, creator: creator, followHint: hint))
    }

    // MARK: Allowed entries

    func testReelSentInDMIsAllowed() {
        var s = Session()
        XCTAssertEqual(send(page("https://www.instagram.com/direct/t/123/"), &s), .allow)
        XCTAssertEqual(send(reel("A", by: "stranger", .notFollowing), &s), .allow)
    }

    func testReelOpenedFromProfileIsAllowed() {
        var s = Session()
        send(page("https://www.instagram.com/friend/"), &s)
        XCTAssertEqual(send(reel("A", by: "friend", .notFollowing), &s), .allow)
    }

    func testSharedLinkWithNoHistoryIsAllowed() {
        var s = Session()
        XCTAssertEqual(send(reel("A", by: nil), &s), .allow)
    }

    func testFollowedReelFromHomeFeedIsAllowed() {
        var s = Session()
        send(page("https://www.instagram.com/"), &s)
        XCTAssertEqual(send(reel("A", by: "friend", .following), &s), .allow)
    }

    // MARK: Blocked entries

    func testReelsTabIsBlocked() {
        var s = Session()
        XCTAssertEqual(send(page("https://www.instagram.com/reels/"), &s), .block(.reelsFeed))
        XCTAssertEqual(send(reel("A", by: "friend", .following), &s), .block(.recommended))
    }

    func testExploreReelIsBlocked() {
        var s = Session()
        XCTAssertEqual(send(page("https://www.instagram.com/explore/"), &s), .allow)
        XCTAssertEqual(send(reel("A", by: "creator", .notFollowing), &s), .block(.recommended))
    }

    func testSuggestedReelInHomeFeedIsBlocked() {
        var s = Session()
        send(page("https://www.instagram.com/"), &s)
        XCTAssertEqual(send(reel("A", by: "brand", .notFollowing), &s), .block(.recommended))
    }

    // MARK: No infinite feed

    func testSwipeChainStopsAtFirstNonFollowedReel() {
        var s = Session()
        s.settings.manualFollows = ["amy", "ben"]
        send(page("https://www.instagram.com/direct/t/1/"), &s)
        XCTAssertEqual(send(reel("1", by: "stranger"), &s), .allow)     // sent in DM
        XCTAssertEqual(send(reel("2", by: "amy"), &s), .allow)          // followed
        XCTAssertEqual(send(reel("3", by: "ben"), &s), .allow)          // followed
        XCTAssertEqual(send(reel("4", by: "influencer", .notFollowing), &s), .block(.notFollowed))
        XCTAssertEqual(send(reel("5", by: nil), &s), .block(.infiniteScroll))
        XCTAssertEqual(s.state.chain?.length, 3)
    }

    func testUnknownCreatorNeverExtendsTheChain() {
        var s = Session()
        send(page("https://www.instagram.com/direct/t/1/"), &s)
        send(reel("1", by: "friend"), &s)
        XCTAssertEqual(send(reel("2", by: nil), &s), .block(.infiniteScroll))
        XCTAssertEqual(send(reel("2", by: "who", .unknown), &s), .block(.infiniteScroll))
    }

    func testSwipingBackToAllowedReelWorks() {
        var s = Session()
        send(page("https://www.instagram.com/direct/t/1/"), &s)
        send(reel("1", by: "friend"), &s)
        XCTAssertEqual(send(reel("2", by: "x", .notFollowing), &s), .block(.notFollowed))
        XCTAssertEqual(send(reel("1", by: "friend"), &s), .allow)
    }

    func testSameCreatorFromProfileCanBeSwiped() {
        var s = Session()
        send(page("https://www.instagram.com/artist/reels/"), &s)
        send(reel("1", by: "artist", .notFollowing), &s)
        XCTAssertEqual(send(reel("2", by: "artist", .notFollowing), &s), .allow)
        XCTAssertEqual(send(reel("3", by: "other", .notFollowing), &s), .block(.notFollowed))
    }

    func testLeavingReelsEndsTheChain() {
        var s = Session()
        send(page("https://www.instagram.com/direct/t/1/"), &s)
        send(reel("1", by: "friend"), &s)
        send(page("https://www.instagram.com/explore/"), &s)
        XCTAssertNil(s.state.chain)
        XCTAssertEqual(send(reel("2", by: "x"), &s), .block(.recommended))
    }

    func testMissingFollowButtonCountsAsFollowingOnlyOutsideStrictMode() {
        var s = Session()
        send(page("https://www.instagram.com/direct/t/1/"), &s)
        send(reel("1", by: "friend"), &s)
        XCTAssertEqual(send(reel("2", by: "pal", .noFollowButton), &s), .allow)

        var strict = Session()
        strict.settings.strictMode = true
        send(page("https://www.instagram.com/direct/t/1/"), &strict)
        send(reel("1", by: "friend"), &strict)
        XCTAssertEqual(send(reel("2", by: "pal", .noFollowButton), &strict), .block(.infiniteScroll))
    }

    // MARK: Settings

    func testDisabledCategoriesAreBlocked() {
        var s = Session()
        s.settings.allowSentReels = false
        s.settings.allowProfileReels = false
        send(page("https://www.instagram.com/direct/t/1/"), &s)
        XCTAssertEqual(send(reel("1", by: "a"), &s), .block(.categoryDisabled(.sentToMe)))
        send(page("https://www.instagram.com/a/"), &s)
        XCTAssertEqual(send(reel("2", by: "a"), &s), .block(.categoryDisabled(.profiles)))
    }

    func testStrictModeRequiresFollowForProfilesAndBlocksExplore() {
        var s = Session()
        s.settings.strictMode = true
        s.settings.allowSentReels = false // ignored in Strict Mode
        XCTAssertEqual(send(page("https://www.instagram.com/explore/"), &s), .block(.explore))
        send(page("https://www.instagram.com/someone/"), &s)
        XCTAssertEqual(send(reel("1", by: "someone", .notFollowing), &s), .block(.notFollowed))
        send(page("https://www.instagram.com/friend/"), &s)
        XCTAssertEqual(send(reel("2", by: "friend", .following), &s), .allow)
        send(page("https://www.instagram.com/direct/t/9/"), &s)
        XCTAssertEqual(send(reel("3", by: "anyone"), &s), .allow)
    }

    func testLearnedFollowsAreUsed() {
        var s = Session()
        s.settings.learnedFollows = ["pal"]
        s.settings.usePageHints = false
        send(page("https://www.instagram.com/direct/t/1/"), &s)
        send(reel("1", by: "friend"), &s)
        XCTAssertEqual(send(reel("2", by: "pal"), &s), .allow)
        XCTAssertEqual(send(reel("3", by: "other", .following), &s), .block(.infiniteScroll))
    }

    // MARK: Time limit

    func testTimeLimitBlocksReelsUntilCooldownEnds() {
        var s = Session()
        s.settings.reelLimit = .five
        s.settings.cooldown = .oneHour
        send(page("https://www.instagram.com/direct/t/1/"), &s)
        XCTAssertEqual(send(reel("1", by: "friend"), &s), .allow)

        var decision: GuardDecision = .allow
        for _ in 0..<60 { decision = send(.watchTick(seconds: 5), &s) } // 300 s
        let until = now.addingTimeInterval(3600)
        XCTAssertEqual(decision, .block(.timeUp(until: until)))
        XCTAssertEqual(send(reel("1", by: "friend"), &s), .block(.timeUp(until: until)))

        // Other pages still work while cooling down.
        XCTAssertEqual(send(page("https://www.instagram.com/"), &s), .allow)

        // After the cooldown, Reels work again and the counter is reset.
        send(page("https://www.instagram.com/direct/t/1/"), &s, at: until.addingTimeInterval(1))
        XCTAssertEqual(send(reel("1", by: "friend"), &s, at: until.addingTimeInterval(2)), .allow)
        XCTAssertEqual(s.budget.secondsUsed, 0)
    }

    func testTicksAreIgnoredWhenLimitIsOffOrReelBlocked() {
        var s = Session()
        send(page("https://www.instagram.com/direct/t/1/"), &s)
        send(reel("1", by: "friend"), &s)
        send(.watchTick(seconds: 5), &s)
        XCTAssertEqual(s.budget.secondsUsed, 0)

        s.settings.reelLimit = .five
        send(reel("2", by: "x", .notFollowing), &s)
        send(.watchTick(seconds: 5), &s)
        XCTAssertEqual(s.budget.secondsUsed, 0)
    }

    func testOversizedTicksAreCapped() {
        var s = Session()
        s.settings.reelLimit = .five
        send(page("https://www.instagram.com/direct/t/1/"), &s)
        send(reel("1", by: "friend"), &s)
        XCTAssertEqual(send(.watchTick(seconds: 10_000), &s), .allow)
        XCTAssertEqual(s.budget.secondsUsed, ReelTimeBudget.maxTick)
    }

    // MARK: Extensibility

    func testCustomRulesRunInOrder() {
        struct BlockEverything: GuardRule {
            let name = "everything"
            func verdict(for context: GuardContext) -> RuleVerdict { context.page.isReel ? .block(.recommended) : .abstain }
        }
        let custom = ReelsGuardEngine(rules: [BlockEverything()] + ReelsGuardEngine.defaultRules)
        let outcome = custom.process(.reel(ReelSighting(reelID: "1", creator: "a")), state: GuardState(lastPage: .directThread),
                                     settings: GuardSettings(), budget: ReelTimeBudget(), now: now)
        XCTAssertEqual(outcome.decision, .block(.recommended))
    }
}
