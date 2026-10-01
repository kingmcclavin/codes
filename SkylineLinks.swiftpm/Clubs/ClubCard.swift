import Foundation

/// The static definition of a collectible club card.
struct ClubCardDefinition: Identifiable, Equatable {
    let id: String
    let name: String
    let type: ClubType
    let rarity: Rarity
    let stats: ClubStats
    let abilities: [ClubAbility]
    let flavor: String

    var isStarter: Bool { id.hasPrefix("starter_") }
}

/// Copies and coins needed to go from `level` to `level + 1`.
enum UpgradeRules {
    static let copiesNeeded = [2, 4, 6, 10, 14, 20, 28, 36, 50]
    static let coinCost = [100, 220, 400, 700, 1100, 1700, 2500, 3500, 5000]

    static func copies(toLevelUpFrom level: Int) -> Int {
        let i = (level - 1).clamped(0, copiesNeeded.count - 1)
        return copiesNeeded[i]
    }

    static func coins(toLevelUpFrom level: Int) -> Int {
        let i = (level - 1).clamped(0, coinCost.count - 1)
        return coinCost[i]
    }
}

/// Every card in the game. Starter cards (one per club type) are given to new players.
enum ClubCatalog {
    static let all: [ClubCardDefinition] = starters + collection

    static func card(_ id: String) -> ClubCardDefinition? {
        byID[id]
    }

    private static let byID: [String: ClubCardDefinition] = {
        var d: [String: ClubCardDefinition] = [:]
        for c in all { d[c.id] = c }
        return d
    }()

    static func cards(of rarity: Rarity) -> [ClubCardDefinition] {
        all.filter { $0.rarity == rarity && !$0.isStarter }
    }

    static func starter(for type: ClubType) -> ClubCardDefinition {
        starters.first { $0.type == type }!
    }

    private static func make(_ id: String, _ name: String, _ type: ClubType, _ rarity: Rarity,
                             _ stats: ClubStats, _ abilities: [ClubAbility] = [], _ flavor: String = "") -> ClubCardDefinition {
        ClubCardDefinition(id: id, name: name, type: type, rarity: rarity, stats: stats, abilities: abilities, flavor: flavor)
    }

    // MARK: Starter set (Power, Accuracy, Forgiveness, Spin, Control)

    static let starters: [ClubCardDefinition] = [
        make("starter_driver", "Clubhouse Driver", .driver, .common, ClubStats(48, 50, 56, 40, 50), [], "Borrowed from the pro shop rack."),
        make("starter_3w", "Clubhouse 3 Wood", .wood3, .common, ClubStats(48, 52, 55, 42, 50)),
        make("starter_5w", "Clubhouse 5 Wood", .wood5, .common, ClubStats(48, 53, 58, 44, 52)),
        make("starter_3i", "Clubhouse 3 Iron", .iron3, .common, ClubStats(48, 52, 48, 46, 50)),
        make("starter_5i", "Clubhouse 5 Iron", .iron5, .common, ClubStats(48, 54, 52, 48, 52)),
        make("starter_7i", "Clubhouse 7 Iron", .iron7, .common, ClubStats(48, 56, 55, 50, 54)),
        make("starter_9i", "Clubhouse 9 Iron", .iron9, .common, ClubStats(48, 58, 56, 52, 55)),
        make("starter_pw", "Clubhouse Wedge", .pitchingWedge, .common, ClubStats(48, 58, 58, 52, 56)),
        make("starter_sw", "Clubhouse Sand Wedge", .sandWedge, .common, ClubStats(48, 56, 56, 54, 55), [ClubAbility.lie("Sand Scoop", .sand, 20)]),
        make("starter_lw", "Clubhouse Lob Wedge", .lobWedge, .common, ClubStats(48, 56, 55, 56, 55)),
        make("starter_putter", "Clubhouse Putter", .putter, .common, ClubStats(50, 55, 55, 0, 55))
    ]

    // MARK: Collectible cards. Note the trade-offs: no card is best everywhere.

    static let collection: [ClubCardDefinition] = [
        // Drivers
        make("range_driver", "Range Rocket", .driver, .common, ClubStats(58, 40, 44, 36, 44), [], "Loud, long and a little wild."),
        make("gale_driver", "Gale Driver", .driver, .uncommon, ClubStats(52, 54, 52, 40, 52), [ClubAbility.wind("Wind Cutter", 25)], "Low, piercing ball flight."),
        make("longhaul_driver", "Long Haul", .driver, .uncommon, ClubStats(66, 42, 40, 36, 46), [ClubAbility.distance("Overdrive", 3)]),
        make("finder_driver", "Fairway Finder", .driver, .rare, ClubStats(52, 74, 72, 44, 64), [ClubAbility.accurate("Laser Line", 15)], "Fairways and greens."),
        make("storm_driver", "Storm Driver", .driver, .epic, ClubStats(92, 64, 51, 45, 55), [ClubAbility.fairway("Fairway Force", 6)], "Bottled lightning."),
        make("skybreaker_driver", "Skybreaker", .driver, .legendary, ClubStats(96, 72, 66, 50, 66), [ClubAbility.distance("Jet Stream", 4), ClubAbility.wind("Eye of the Storm", 30)], "Legends say it once cleared a lake."),

        // 3 Woods
        make("turf_3w", "Turf Rider", .wood3, .uncommon, ClubStats(52, 52, 56, 42, 52), [ClubAbility.lie("Rough Glide", .rough, 40)]),
        make("tempest_3w", "Tempest 3 Wood", .wood3, .rare, ClubStats(62, 60, 54, 44, 56), [ClubAbility.wind("Gust Guard", 35)]),
        make("comet_3w", "Comet Spoon", .wood3, .epic, ClubStats(86, 62, 50, 46, 58), [ClubAbility.fairway("Tail Fire", 5)]),
        make("park_3w", "Parkland Spoon", .wood3, .common, ClubStats(54, 48, 54, 40, 48)),

        // 5 Woods
        make("meadow_5w", "Meadow 5 Wood", .wood5, .uncommon, ClubStats(52, 56, 66, 46, 56), [ClubAbility.forgive("Soft Landing", 20)]),
        make("rescue_5w", "Rescue Five", .wood5, .rare, ClubStats(56, 58, 70, 46, 58), [ClubAbility.lie("Jungle Escape", .heavyRough, 55)], "Gets you out of trouble."),
        make("nova_5w", "Nova Five", .wood5, .legendary, ClubStats(84, 76, 78, 54, 70), [ClubAbility.lie("Weedwhacker", .rough, 70), ClubAbility.forgive("Halo", 20)]),

        // 3 Irons
        make("blade_3i", "Blade 3 Iron", .iron3, .uncommon, ClubStats(58, 72, 34, 50, 58), [], "Pure, unforgiving, beautiful."),
        make("anvil_3i", "Anvil 3 Iron", .iron3, .common, ClubStats(52, 46, 54, 44, 46)),
        make("thunder_3i", "Thunder 3 Iron", .iron3, .epic, ClubStats(88, 66, 50, 52, 62), [ClubAbility.wind("Stinger", 30)]),

        // 5 Irons
        make("roughrider_5i", "Rough Rider 5 Iron", .iron5, .uncommon, ClubStats(52, 54, 58, 48, 52), [ClubAbility.lie("Rough Force", .rough, 50)]),
        make("precision_5i", "Precision 5 Iron", .iron5, .rare, ClubStats(54, 80, 52, 52, 66), [ClubAbility.accurate("Dial In", 20)]),
        make("canyon_5i", "Canyon 5 Iron", .iron5, .common, ClubStats(56, 50, 50, 46, 48)),

        // 7 Irons
        make("roughmaster_7i", "Roughmaster 7 Iron", .iron7, .rare, ClubStats(70, 82, 91, 56, 64), [ClubAbility.lie("Rough Force", .rough, 80)], "Made for the long grass."),
        make("tide_7i", "Tidewater 7 Iron", .iron7, .uncommon, ClubStats(52, 60, 56, 52, 56), [ClubAbility.wind("Sea Breeze", 25)]),
        make("solar_7i", "Solar Flare 7 Iron", .iron7, .legendary, ClubStats(90, 84, 70, 66, 74), [ClubAbility.accurate("Sunbeam", 20), ClubAbility.lie("Scorch", .rough, 60)]),
        make("park_7i", "Parkland 7 Iron", .iron7, .common, ClubStats(54, 54, 52, 48, 50)),

        // 9 Irons
        make("dart_9i", "Dart 9 Iron", .iron9, .uncommon, ClubStats(50, 62, 56, 54, 58), [ClubAbility.shortGame("Bullseye", 25)]),
        make("backdraft_9i", "Backdraft 9 Iron", .iron9, .rare, ClubStats(56, 64, 58, 72, 60), [ClubAbility.spin("Reverse Thrust", 40)], "Lands, hops, sucks back."),
        make("forge_9i", "Forge 9 Iron", .iron9, .common, ClubStats(56, 52, 52, 50, 50)),

        // Pitching wedges
        make("pinseeker_pw", "Pinseeker Wedge", .pitchingWedge, .rare, ClubStats(54, 72, 60, 60, 66), [ClubAbility.shortGame("Flag Hunter", 35, 120)]),
        make("velvet_pw", "Velvet Wedge", .pitchingWedge, .epic, ClubStats(66, 74, 66, 86, 70), [ClubAbility.spin("Velvet Touch", 45), ClubAbility.accurate("Smooth", 10)]),
        make("garden_pw", "Garden Wedge", .pitchingWedge, .common, ClubStats(52, 56, 60, 50, 54)),

        // Sand wedges
        make("dune_sw", "Dune Buster", .sandWedge, .rare, ClubStats(54, 60, 64, 62, 60), [ClubAbility.lie("Sand Blast", .sand, 50)]),
        make("sahara_sw", "Sahara Sand Wedge", .sandWedge, .epic, ClubStats(62, 66, 70, 70, 64), [ClubAbility.lie("Desert Storm", .sand, 85), ClubAbility.lie("Thicket", .heavyRough, 40)]),
        make("beach_sw", "Beach Wedge", .sandWedge, .uncommon, ClubStats(50, 58, 62, 58, 56), [ClubAbility.lie("Sand Scoop", .sand, 35)]),

        // Lob wedges
        make("feather_lw", "Feather Lob", .lobWedge, .uncommon, ClubStats(50, 58, 70, 60, 58), [ClubAbility.forgive("Featherlight", 30)]),
        make("halo_lw", "Halo Lob Wedge", .lobWedge, .legendary, ClubStats(74, 86, 76, 92, 78), [ClubAbility.spin("Hover", 60), ClubAbility.shortGame("Angel Touch", 40, 100)]),
        make("flop_lw", "Flop Shot", .lobWedge, .common, ClubStats(52, 54, 52, 62, 50)),

        // Putters
        make("steady_putter", "Steady Roller", .putter, .uncommon, ClubStats(52, 62, 60, 0, 60), [ClubAbility.putting("Steady Hands", 20)]),
        make("silk_putter", "Silk Line", .putter, .rare, ClubStats(54, 72, 64, 0, 68), [ClubAbility.putting("True Roll", 35)]),
        make("oracle_putter", "Oracle Putter", .putter, .legendary, ClubStats(60, 88, 76, 0, 80), [ClubAbility.putting("Second Sight", 60)], "Sees every break."),
        make("mallet_putter", "Mallet Mate", .putter, .common, ClubStats(54, 56, 60, 0, 52)),
        make("epic_putter", "Moonwalker Putter", .putter, .epic, ClubStats(58, 80, 70, 0, 74), [ClubAbility.putting("Lunar Glide", 45)])
    ]
}
