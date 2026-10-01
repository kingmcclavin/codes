import Foundation

enum PackType: String, CaseIterable, Identifiable {
    case basic
    case premium
    case elite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .basic: return "Basic Pack"
        case .premium: return "Premium Pack"
        case .elite: return "Elite Pack"
        }
    }

    var price: Int {
        switch self {
        case .basic: return 400
        case .premium: return 1200
        case .elite: return 3000
        }
    }

    var cardCount: Int {
        switch self {
        case .basic: return 3
        case .premium: return 4
        case .elite: return 5
        }
    }

    /// Per-card rarity odds. These are shown to the player exactly as used.
    var odds: [(Rarity, Double)] {
        switch self {
        case .basic: return [(.common, 0.70), (.uncommon, 0.25), (.rare, 0.05)]
        case .premium: return [(.uncommon, 0.50), (.rare, 0.40), (.epic, 0.10)]
        case .elite: return [(.rare, 0.60), (.epic, 0.32), (.legendary, 0.08)]
        }
    }

    var color: RGBColor {
        switch self {
        case .basic: return RGBColor(hex: 0x4FA35B)
        case .premium: return RGBColor(hex: 0x3D7BE0)
        case .elite: return RGBColor(hex: 0xC9902A)
        }
    }
}

struct PackReveal: Identifiable {
    let id = UUID()
    let card: ClubCardDefinition
    let isNew: Bool
    let level: Int
    let copies: Int
    let copiesNeeded: Int
}

enum PackSystem {
    static func rollRarity(_ pack: PackType, rng: inout SeededRandom) -> Rarity {
        let roll = rng.range(0, 1)
        var acc = 0.0
        for (rarity, p) in pack.odds {
            acc += p
            if roll < acc { return rarity }
        }
        return pack.odds.last?.0 ?? .common
    }

    static func draw(_ pack: PackType, rng: inout SeededRandom) -> [ClubCardDefinition] {
        var result: [ClubCardDefinition] = []
        for _ in 0..<pack.cardCount {
            let rarity = rollRarity(pack, rng: &rng)
            var pool = ClubCatalog.cards(of: rarity)
            if pool.isEmpty { pool = ClubCatalog.cards(of: .common) }
            result.append(rng.pick(pool))
        }
        // Show the best card last for a satisfying reveal.
        return result.sorted { $0.rarity < $1.rarity }
    }

    /// Spends coins, adds the cards and returns what to show. Nil if the player cannot afford it.
    static func buy(_ pack: PackType, progress: inout PlayerProgress, rng: inout SeededRandom) -> [PackReveal]? {
        guard progress.coins >= pack.price else { return nil }
        progress.coins -= pack.price
        progress.packsOpened += 1
        let cards = draw(pack, rng: &rng)
        var reveals: [PackReveal] = []
        for card in cards {
            let isNew = progress.addCard(card.id)
            let owned = progress.cards[card.id] ?? OwnedCard(level: 1, copies: 0)
            reveals.append(PackReveal(card: card, isNew: isNew, level: owned.level, copies: owned.copies,
                                      copiesNeeded: UpgradeRules.copies(toLevelUpFrom: owned.level)))
        }
        return reveals
    }
}
