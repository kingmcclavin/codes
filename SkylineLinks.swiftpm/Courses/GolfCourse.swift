import Foundation

enum DecorStyle {
    case broadleaf
    case pine
    case palm
    case cactus
    case rock
    case snowPine
}

struct CourseTheme {
    let fairway: RGBColor
    let rough: RGBColor
    let heavyRough: RGBColor
    let green: RGBColor
    let fringe: RGBColor
    let sand: RGBColor
    let water: RGBColor
    let outOfBounds: RGBColor
    let decor: RGBColor
    let decorStyle: DecorStyle
    let hazardName: String
    let skyTop: RGBColor
    let skyBottom: RGBColor
    let windBonus: Double
    let greenSpeed: Double
    let par3Styles: [HoleArchetype]
    let par4Styles: [HoleArchetype]
    let par5Styles: [HoleArchetype]
}

enum RoundLength: Int, CaseIterable, Identifiable, Codable {
    case quick = 3
    case front = 9
    case full = 18

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .quick: return "Quick 3"
        case .front: return "9 Holes"
        case .full: return "18 Holes"
        }
    }
}

struct GolfCourse: Identifiable {
    let id: String
    let index: Int
    let name: String
    let tagline: String
    let difficulty: Int
    let theme: CourseTheme
    let rivalName: String
    let holes: [GolfHole]

    func holes(for length: RoundLength) -> [GolfHole] {
        Array(holes.prefix(length.rawValue))
    }

    func par(for length: RoundLength) -> Int {
        holes(for: length).reduce(0) { $0 + $1.par }
    }

    /// The rival's score relative to par. This is the number to match or beat.
    func target(for length: RoundLength) -> Int {
        holes(for: length).reduce(0) { $0 + ($1.botStrokes - $1.par) }
    }
}
