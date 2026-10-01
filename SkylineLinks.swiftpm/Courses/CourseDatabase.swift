import Foundation

/// Light description of a course. Holes are generated on demand from this data.
struct CourseInfo {
    let id: String
    let name: String
    let tagline: String
    let difficulty: Int
    let rivalName: String
    let theme: CourseTheme
    /// Optional hand-picked blueprints for the first holes (used by the tutorial course).
    var openingHoles: [HoleBlueprint] = []
}

enum CourseDatabase {
    static let frontPars = [4, 4, 3, 5, 4, 3, 4, 5, 4]
    static let backPars = [4, 3, 4, 5, 4, 4, 3, 5, 4]

    static var count: Int { infos.count }

    static func course(_ index: Int) -> GolfCourse {
        CourseLibrary.shared.course(index)
    }

    static func build(_ index: Int) -> GolfCourse {
        let info = infos[index]
        let pars = frontPars + backPars
        let rate = min(0.75, 0.22 + Double(info.difficulty) * 0.05)
        var holes: [GolfHole] = []
        var c3 = 0
        var c4 = 0
        var c5 = 0
        for i in 0..<pars.count {
            let bp: HoleBlueprint
            if i < info.openingHoles.count {
                bp = info.openingHoles[i]
            } else {
                let par = pars[i]
                let styles: [HoleArchetype]
                let pick: Int
                switch par {
                case 3:
                    styles = info.theme.par3Styles
                    pick = c3
                    c3 += 1
                case 5:
                    styles = info.theme.par5Styles
                    pick = c5
                    c5 += 1
                default:
                    styles = info.theme.par4Styles
                    pick = c4
                    c4 += 1
                }
                bp = HoleBlueprint(par: par, archetype: styles[(pick + index) % styles.count])
            }

            // Spread the rival's birdies evenly through the round.
            let birdieNow = Int((Double(i + 1) * rate + 0.35).rounded(.down)) > Int((Double(i) * rate + 0.35).rounded(.down))
            var bot = bp.par
            if birdieNow {
                bot -= 1
                if bp.par == 5 && info.difficulty >= 7 && i % 2 == 1 { bot -= 1 }
            }

            let seed = UInt64(index + 1) &* 1_000_003 &+ UInt64(i) &* 7919
            holes.append(CourseGenerator.makeHole(number: i + 1, blueprint: bp, theme: info.theme, difficulty: info.difficulty, botStrokes: bot, seed: seed))
        }
        return GolfCourse(id: info.id, index: index, name: info.name, tagline: info.tagline, difficulty: info.difficulty,
                          theme: info.theme, rivalName: info.rivalName, holes: holes)
    }

    // MARK: - Course list (campaign order)

    static let infos: [CourseInfo] = [
        CourseInfo(
            id: "clover_meadows", name: "Clover Meadows", tagline: "Gentle hills and friendly fairways.",
            difficulty: 1, rivalName: "Rookie Rowan",
            theme: CourseTheme(
                fairway: RGBColor(hex: 0x6CC24A), rough: RGBColor(hex: 0x4E9A3A), heavyRough: RGBColor(hex: 0x3A7A2E),
                green: RGBColor(hex: 0x86D867), fringe: RGBColor(hex: 0x74C957), sand: RGBColor(hex: 0xEED9A0),
                water: RGBColor(hex: 0x3D9BE0), outOfBounds: RGBColor(hex: 0x2C5E25), decor: RGBColor(hex: 0x2F6B2A),
                decorStyle: .broadleaf, hazardName: "Water",
                skyTop: RGBColor(hex: 0x8FD3FF), skyBottom: RGBColor(hex: 0xC9F2B0),
                windBonus: 0, greenSpeed: 1.0,
                par3Styles: [.bunkerComplex, .waterCrossing, .straight],
                par4Styles: [.straight, .doglegRight, .doglegLeft, .bunkerComplex],
                par5Styles: [.straight, .doglegLeft]
            ),
            openingHoles: [
                HoleBlueprint(par: 4, archetype: .straight, calm: true, lengthBias: -15),
                HoleBlueprint(par: 4, archetype: .doglegRight),
                HoleBlueprint(par: 3, archetype: .bunkerComplex)
            ]
        ),
        CourseInfo(
            id: "sandpiper_dunes", name: "Sandpiper Dunes", tagline: "Links golf among the dunes. Mind the pot bunkers.",
            difficulty: 2, rivalName: "Dune Dana",
            theme: CourseTheme(
                fairway: RGBColor(hex: 0x9CC45A), rough: RGBColor(hex: 0x86A94A), heavyRough: RGBColor(hex: 0xB9B07A),
                green: RGBColor(hex: 0xA9D66B), fringe: RGBColor(hex: 0x98C95E), sand: RGBColor(hex: 0xF1DFA8),
                water: RGBColor(hex: 0x4A8FC2), outOfBounds: RGBColor(hex: 0xD8CB94), decor: RGBColor(hex: 0x8F8A6A),
                decorStyle: .rock, hazardName: "Water",
                skyTop: RGBColor(hex: 0xA6D8F5), skyBottom: RGBColor(hex: 0xF3E6B5),
                windBonus: 4, greenSpeed: 0.95,
                par3Styles: [.bunkerComplex, .straight],
                par4Styles: [.bunkerComplex, .doglegLeft, .straight, .splitFairway],
                par5Styles: [.bunkerComplex, .doglegRight]
            )
        ),
        CourseInfo(
            id: "redrock_mesa", name: "Redrock Mesa", tagline: "Desert target golf between towering cacti.",
            difficulty: 3, rivalName: "Mesa Max",
            theme: CourseTheme(
                fairway: RGBColor(hex: 0x7DBE4F), rough: RGBColor(hex: 0x9C9A55), heavyRough: RGBColor(hex: 0xD2A46A),
                green: RGBColor(hex: 0x8DD164), fringe: RGBColor(hex: 0x82C258), sand: RGBColor(hex: 0xF0C98A),
                water: RGBColor(hex: 0x2FA3C6), outOfBounds: RGBColor(hex: 0xB9773F), decor: RGBColor(hex: 0x4F8A3C),
                decorStyle: .cactus, hazardName: "Water",
                skyTop: RGBColor(hex: 0xFFB36B), skyBottom: RGBColor(hex: 0xFFE2A8),
                windBonus: 2, greenSpeed: 0.92,
                par3Styles: [.elevatedGreen, .waterCrossing, .mountain],
                par4Styles: [.doglegLeft, .elevatedGreen, .narrow, .straight],
                par5Styles: [.splitFairway, .doglegRight]
            )
        ),
        CourseInfo(
            id: "whispering_pines", name: "Whispering Pines", tagline: "Tree-lined chutes. Accuracy beats power.",
            difficulty: 4, rivalName: "Pinecone Priya",
            theme: CourseTheme(
                fairway: RGBColor(hex: 0x5DB04A), rough: RGBColor(hex: 0x3F8A38), heavyRough: RGBColor(hex: 0x2E6A2C),
                green: RGBColor(hex: 0x79CF62), fringe: RGBColor(hex: 0x68BF55), sand: RGBColor(hex: 0xE9DDB4),
                water: RGBColor(hex: 0x2F7FB8), outOfBounds: RGBColor(hex: 0x1F4A1E), decor: RGBColor(hex: 0x1E5A2C),
                decorStyle: .pine, hazardName: "Water",
                skyTop: RGBColor(hex: 0x7FB8D8), skyBottom: RGBColor(hex: 0xBFE3C8),
                windBonus: 0, greenSpeed: 0.95,
                par3Styles: [.straight, .elevatedGreen],
                par4Styles: [.narrow, .doglegLeft, .doglegRight, .straight],
                par5Styles: [.doglegLeft, .narrow]
            )
        ),
        CourseInfo(
            id: "saltspray_cliffs", name: "Saltspray Cliffs", tagline: "Ocean on one side, wind on all of them.",
            difficulty: 5, rivalName: "Captain Cora",
            theme: CourseTheme(
                fairway: RGBColor(hex: 0x6BBF55), rough: RGBColor(hex: 0x56A045), heavyRough: RGBColor(hex: 0x8A9A6A),
                green: RGBColor(hex: 0x82D46A), fringe: RGBColor(hex: 0x73C55C), sand: RGBColor(hex: 0xF2E3B8),
                water: RGBColor(hex: 0x1F6FB2), outOfBounds: RGBColor(hex: 0x6B6F5A), decor: RGBColor(hex: 0x7C7F70),
                decorStyle: .rock, hazardName: "Ocean",
                skyTop: RGBColor(hex: 0x6EC6FF), skyBottom: RGBColor(hex: 0xD6F0FF),
                windBonus: 6, greenSpeed: 0.92,
                par3Styles: [.coastal, .islandGreen],
                par4Styles: [.coastal, .doglegRight, .waterCrossing],
                par5Styles: [.coastal, .splitFairway]
            )
        ),
        CourseInfo(
            id: "emberpeak_ridge", name: "Emberpeak Ridge", tagline: "Volcanic fairways over rivers of lava.",
            difficulty: 6, rivalName: "Ember Eli",
            theme: CourseTheme(
                fairway: RGBColor(hex: 0x6FAE4A), rough: RGBColor(hex: 0x56704A), heavyRough: RGBColor(hex: 0x3C3A3E),
                green: RGBColor(hex: 0x86C95E), fringe: RGBColor(hex: 0x76B653), sand: RGBColor(hex: 0x8A8580),
                water: RGBColor(hex: 0xF0602A), outOfBounds: RGBColor(hex: 0x252327), decor: RGBColor(hex: 0x4A4548),
                decorStyle: .rock, hazardName: "Lava",
                skyTop: RGBColor(hex: 0x5A2A3A), skyBottom: RGBColor(hex: 0xF08A4B),
                windBonus: 3, greenSpeed: 0.9,
                par3Styles: [.islandGreen, .mountain],
                par4Styles: [.waterCrossing, .mountain, .doglegLeft, .elevatedGreen],
                par5Styles: [.splitFairway, .waterCrossing]
            )
        ),
        CourseInfo(
            id: "glacier_crown", name: "Glacier Crown", tagline: "Alpine drops and lightning-fast greens.",
            difficulty: 7, rivalName: "Frost Freya",
            theme: CourseTheme(
                fairway: RGBColor(hex: 0x66B65A), rough: RGBColor(hex: 0x5C8F6A), heavyRough: RGBColor(hex: 0xDDE8EE),
                green: RGBColor(hex: 0x7FD07A), fringe: RGBColor(hex: 0x70C06C), sand: RGBColor(hex: 0xE6E0D2),
                water: RGBColor(hex: 0x7CC6E8), outOfBounds: RGBColor(hex: 0xC4D3DC), decor: RGBColor(hex: 0x2D5A48),
                decorStyle: .snowPine, hazardName: "Glacier Lake",
                skyTop: RGBColor(hex: 0x6A9FD8), skyBottom: RGBColor(hex: 0xE8F4FF),
                windBonus: 3, greenSpeed: 0.78,
                par3Styles: [.mountain, .elevatedGreen],
                par4Styles: [.mountain, .doglegRight, .narrow],
                par5Styles: [.mountain, .doglegLeft]
            )
        ),
        CourseInfo(
            id: "coral_atoll", name: "Coral Atoll", tagline: "Island hopping across turquoise lagoons.",
            difficulty: 8, rivalName: "Coral Kai",
            theme: CourseTheme(
                fairway: RGBColor(hex: 0x6FCB5A), rough: RGBColor(hex: 0x58AE4A), heavyRough: RGBColor(hex: 0xEFE2B0),
                green: RGBColor(hex: 0x8BE070), fringe: RGBColor(hex: 0x7BD062), sand: RGBColor(hex: 0xFFF1C9),
                water: RGBColor(hex: 0x21B8C9), outOfBounds: RGBColor(hex: 0x1593B5), decor: RGBColor(hex: 0x3C8C3A),
                decorStyle: .palm, hazardName: "Lagoon",
                skyTop: RGBColor(hex: 0x4FD1E8), skyBottom: RGBColor(hex: 0xFFF3C4),
                windBonus: 5, greenSpeed: 0.9,
                par3Styles: [.islandGreen, .waterCrossing],
                par4Styles: [.waterCrossing, .coastal, .splitFairway],
                par5Styles: [.waterCrossing, .coastal]
            )
        ),
        CourseInfo(
            id: "thistle_highlands", name: "Thistle Highlands", tagline: "Wild heather, deep pots and howling wind.",
            difficulty: 9, rivalName: "Highland Hamish",
            theme: CourseTheme(
                fairway: RGBColor(hex: 0x8DB85A), rough: RGBColor(hex: 0x7A8F4A), heavyRough: RGBColor(hex: 0x8A6A8A),
                green: RGBColor(hex: 0x9ACB66), fringe: RGBColor(hex: 0x8BBE5A), sand: RGBColor(hex: 0xE4D6A8),
                water: RGBColor(hex: 0x4B6E8E), outOfBounds: RGBColor(hex: 0x5A4A5E), decor: RGBColor(hex: 0x6A6A62),
                decorStyle: .rock, hazardName: "Burn",
                skyTop: RGBColor(hex: 0x8C9BB0), skyBottom: RGBColor(hex: 0xD8D2C8),
                windBonus: 8, greenSpeed: 0.92,
                par3Styles: [.bunkerComplex, .straight],
                par4Styles: [.narrow, .bunkerComplex, .doglegLeft],
                par5Styles: [.bunkerComplex, .splitFairway]
            )
        ),
        CourseInfo(
            id: "grand_summit", name: "Grand Summit", tagline: "The championship test. Every hazard, every wind.",
            difficulty: 10, rivalName: "Grandmaster Gale",
            theme: CourseTheme(
                fairway: RGBColor(hex: 0x5FBF52), rough: RGBColor(hex: 0x469A40), heavyRough: RGBColor(hex: 0x2F6E31),
                green: RGBColor(hex: 0x7EDB6A), fringe: RGBColor(hex: 0x6ECB5C), sand: RGBColor(hex: 0xF4E7C0),
                water: RGBColor(hex: 0x2C86D1), outOfBounds: RGBColor(hex: 0x1D4A22), decor: RGBColor(hex: 0x245E2A),
                decorStyle: .broadleaf, hazardName: "Water",
                skyTop: RGBColor(hex: 0x3E6FD8), skyBottom: RGBColor(hex: 0xF6D58A),
                windBonus: 5, greenSpeed: 0.84,
                par3Styles: [.islandGreen, .elevatedGreen, .waterCrossing, .bunkerComplex],
                par4Styles: [.doglegLeft, .narrow, .waterCrossing, .splitFairway, .doglegRight, .elevatedGreen],
                par5Styles: [.splitFairway, .waterCrossing, .doglegRight]
            )
        )
    ]
}

/// Caches generated courses (generation is cheap but not free).
final class CourseLibrary {
    static let shared = CourseLibrary()
    private var cache: [Int: GolfCourse] = [:]

    func course(_ index: Int) -> GolfCourse {
        let i = index.clamped(0, CourseDatabase.infos.count - 1)
        if let c = cache[i] { return c }
        let c = CourseDatabase.build(i)
        cache[i] = c
        return c
    }
}
