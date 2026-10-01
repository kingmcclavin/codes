import Foundation

struct OwnedCard: Codable, Equatable {
    var level: Int
    /// Duplicate copies collected toward the next level.
    var copies: Int
}

/// Everything that is saved between launches.
struct PlayerProgress: Codable {
    var coins: Int = 600
    var xp: Int = 0
    /// Number of campaign courses unlocked (course index < this value is playable).
    var unlockedCourses: Int = 1
    /// Best score to par, keyed by "courseId-holes".
    var bestScores: [String: Int] = [:]
    /// Courses whose target has been beaten, keyed by "courseId-holes".
    var beatenTargets: Set<String> = []
    var cards: [String: OwnedCard] = [:]
    /// ClubType raw value -> card id.
    var equipped: [String: String] = [:]
    var completedChallenges: Set<String> = []
    var roundsPlayed: Int = 0
    var holesInOne: Int = 0
    var birdiesOrBetter: Int = 0
    var packsOpened: Int = 0
    var hapticsOn: Bool = true
    var soundOn: Bool = true
    var showTutorial: Bool = true

    init() {}

    static func newPlayer() -> PlayerProgress {
        var p = PlayerProgress()
        p.ensureStarterSet()
        return p
    }

    // Tolerant decoding so older saves keep working when new fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        coins = try c.decodeIfPresent(Int.self, forKey: .coins) ?? 600
        xp = try c.decodeIfPresent(Int.self, forKey: .xp) ?? 0
        unlockedCourses = try c.decodeIfPresent(Int.self, forKey: .unlockedCourses) ?? 1
        bestScores = try c.decodeIfPresent([String: Int].self, forKey: .bestScores) ?? [:]
        beatenTargets = try c.decodeIfPresent(Set<String>.self, forKey: .beatenTargets) ?? []
        cards = try c.decodeIfPresent([String: OwnedCard].self, forKey: .cards) ?? [:]
        equipped = try c.decodeIfPresent([String: String].self, forKey: .equipped) ?? [:]
        completedChallenges = try c.decodeIfPresent(Set<String>.self, forKey: .completedChallenges) ?? []
        roundsPlayed = try c.decodeIfPresent(Int.self, forKey: .roundsPlayed) ?? 0
        holesInOne = try c.decodeIfPresent(Int.self, forKey: .holesInOne) ?? 0
        birdiesOrBetter = try c.decodeIfPresent(Int.self, forKey: .birdiesOrBetter) ?? 0
        packsOpened = try c.decodeIfPresent(Int.self, forKey: .packsOpened) ?? 0
        hapticsOn = try c.decodeIfPresent(Bool.self, forKey: .hapticsOn) ?? true
        soundOn = try c.decodeIfPresent(Bool.self, forKey: .soundOn) ?? true
        showTutorial = try c.decodeIfPresent(Bool.self, forKey: .showTutorial) ?? true
        ensureStarterSet()
    }

    // MARK: Level

    static let xpPerLevel = 400

    var playerLevel: Int { xp / PlayerProgress.xpPerLevel + 1 }
    var xpIntoLevel: Int { xp % PlayerProgress.xpPerLevel }

    // MARK: Cards and bag

    mutating func ensureStarterSet() {
        for type in ClubType.allCases {
            let starter = ClubCatalog.starter(for: type)
            if cards[starter.id] == nil {
                cards[starter.id] = OwnedCard(level: 1, copies: 0)
            }
            if let current = equipped[type.rawValue], cards[current] != nil, ClubCatalog.card(current)?.type == type {
                continue
            }
            equipped[type.rawValue] = starter.id
        }
    }

    func owns(_ cardID: String) -> Bool { cards[cardID] != nil }

    func equippedCard(for type: ClubType) -> ClubCardDefinition {
        if let id = equipped[type.rawValue], let card = ClubCatalog.card(id) { return card }
        return ClubCatalog.starter(for: type)
    }

    func bag() -> [ClubType: EquippedClub] {
        var result: [ClubType: EquippedClub] = [:]
        for type in ClubType.allCases {
            let card = equippedCard(for: type)
            let level = cards[card.id]?.level ?? 1
            result[type] = EquippedClub(card: card, level: level)
        }
        return result
    }

    mutating func equip(_ cardID: String) {
        guard let card = ClubCatalog.card(cardID), owns(cardID) else { return }
        equipped[card.type.rawValue] = cardID
    }

    /// Adds a card from a pack. Returns true if the card is new to the collection.
    @discardableResult
    mutating func addCard(_ cardID: String) -> Bool {
        if var owned = cards[cardID] {
            owned.copies += 1
            cards[cardID] = owned
            return false
        }
        cards[cardID] = OwnedCard(level: 1, copies: 0)
        return true
    }

    func canUpgrade(_ cardID: String) -> Bool {
        guard let owned = cards[cardID], let card = ClubCatalog.card(cardID) else { return false }
        if owned.level >= card.rarity.maxLevel { return false }
        return owned.copies >= UpgradeRules.copies(toLevelUpFrom: owned.level)
            && coins >= UpgradeRules.coins(toLevelUpFrom: owned.level)
    }

    @discardableResult
    mutating func upgrade(_ cardID: String) -> Bool {
        guard canUpgrade(cardID), var owned = cards[cardID] else { return false }
        coins -= UpgradeRules.coins(toLevelUpFrom: owned.level)
        owned.copies -= UpgradeRules.copies(toLevelUpFrom: owned.level)
        owned.level += 1
        cards[cardID] = owned
        return true
    }

    // MARK: Courses

    static func scoreKey(courseID: String, length: RoundLength) -> String {
        "\(courseID)-\(length.rawValue)"
    }

    func isUnlocked(courseIndex: Int) -> Bool {
        courseIndex < unlockedCourses
    }

    func bestScore(courseID: String, length: RoundLength) -> Int? {
        bestScores[PlayerProgress.scoreKey(courseID: courseID, length: length)]
    }

    func hasBeaten(courseID: String, length: RoundLength) -> Bool {
        beatenTargets.contains(PlayerProgress.scoreKey(courseID: courseID, length: length))
    }

    /// Index of the furthest unlocked course (what PLAY continues).
    var currentCampaignIndex: Int {
        max(0, min(unlockedCourses, CourseDatabase.count) - 1)
    }
}
