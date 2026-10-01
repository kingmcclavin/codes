import XCTest
@testable import ReelsGuardCore

final class InstagramURLClassifierTests: XCTestCase {
    private func kind(_ s: String) -> PageKind { InstagramURLClassifier.classify(s) }

    func testClassification() {
        XCTAssertEqual(kind("https://www.instagram.com/"), .home)
        XCTAssertEqual(kind("https://www.instagram.com/reels/"), .reelsFeed)
        XCTAssertEqual(kind("https://www.instagram.com/reels/C1abc/"), .reel(id: "C1abc", author: nil))
        XCTAssertEqual(kind("https://www.instagram.com/reel/C1abc/?igsh=x"), .reel(id: "C1abc", author: nil))
        XCTAssertEqual(kind("https://instagram.com/Friend.Name/reel/C1abc/"), .reel(id: "C1abc", author: "friend.name"))
        XCTAssertEqual(kind("https://www.instagram.com/reels/audio/123/"), .explore)
        XCTAssertEqual(kind("https://www.instagram.com/explore/search/"), .explore)
        XCTAssertEqual(kind("https://www.instagram.com/direct/inbox/"), .directInbox)
        XCTAssertEqual(kind("https://www.instagram.com/direct/t/1234/"), .directThread)
        XCTAssertEqual(kind("https://www.instagram.com/friend/"), .profile(username: "friend"))
        XCTAssertEqual(kind("https://www.instagram.com/friend/reels/"), .profile(username: "friend"))
        XCTAssertEqual(kind("https://www.instagram.com/p/xyz/"), .post)
        XCTAssertEqual(kind("https://www.instagram.com/accounts/login/"), .other)
        XCTAssertEqual(kind("https://example.com/reels/"), .other)
    }
}

final class ReelLinkParserTests: XCTestCase {
    func testExtractsAndNormalizesReelLink() {
        let text = "Check this out https://www.instagram.com/reel/C1abc/?igsh=tracking lol"
        XCTAssertEqual(ReelLinkParser.instagramURL(in: text)?.absoluteString, "https://www.instagram.com/reel/C1abc/")
        XCTAssertNil(ReelLinkParser.instagramURL(in: "https://www.instagram.com/explore/"))
        XCTAssertNil(ReelLinkParser.instagramURL(in: "https://example.com/reel/1/"))
    }
}

final class ReelsGuardServiceTests: XCTestCase {
    private func makeService() -> ReelsGuardService {
        let defaults = UserDefaults(suiteName: "ReelsGuardServiceTests-\(UUID().uuidString)")!
        return ReelsGuardService(store: SharedStore(defaults: defaults))
    }

    func testStatelessRoundTripBlocksSwipeToRecommendedReel() {
        let service = makeService()
        var r = service.handleStateless(WireRequest(type: .page, url: "https://www.instagram.com/direct/t/1/"))
        XCTAssertEqual(r.decision, "allow")
        r = service.handleStateless(WireRequest(type: .reel, url: "https://www.instagram.com/reel/A/", reelID: "A",
                                                creator: "friend", stateJSON: r.stateJSON))
        XCTAssertEqual(r.decision, "allow")
        r = service.handleStateless(WireRequest(type: .reel, url: "https://www.instagram.com/reel/B/", reelID: "B",
                                                creator: "brand", followHint: .notFollowing, stateJSON: r.stateJSON))
        XCTAssertEqual(r.decision, "block")
        XCTAssertEqual(r.block?.message, "This Reel isn't from an account you follow.")
        XCTAssertEqual(r.block?.buttonTitle, "Back to Instagram")
    }

    func testDictionaryInterfaceToleratesGarbage() {
        let service = makeService()
        XCTAssertEqual(service.handleStateless(message: nil)["decision"] as? String, "allow")
        XCTAssertEqual(service.handleStateless(message: ["type": "nonsense"])["decision"] as? String, "allow")
        let r = service.handleStateless(message: ["type": "page", "url": "https://www.instagram.com/reels/"])
        XCTAssertEqual(r["decision"] as? String, "block")
    }

    func testProfileVisitsTeachFollows() {
        let service = makeService()
        _ = service.handle(WireRequest(type: .profile, username: "Pal", following: true), state: GuardState())
        XCTAssertEqual(service.store.loadSettings().learnedFollows, ["pal"])
        _ = service.handle(WireRequest(type: .profile, username: "pal", following: false), state: GuardState())
        XCTAssertEqual(service.store.loadSettings().learnedFollows, [])

        service.store.updateSettings { $0.learnFollowsFromProfiles = false }
        _ = service.handle(WireRequest(type: .profile, username: "pal", following: true), state: GuardState())
        XCTAssertEqual(service.store.loadSettings().learnedFollows, [])
    }

    func testSettingsDecodeWithMissingFields() throws {
        let data = Data(#"{"strictMode": true}"#.utf8)
        let settings = try JSONDecoder().decode(GuardSettings.self, from: data)
        XCTAssertTrue(settings.strictMode)
        XCTAssertTrue(settings.allowSentReels)
        XCTAssertEqual(settings.reelLimit, .off)
    }
}
