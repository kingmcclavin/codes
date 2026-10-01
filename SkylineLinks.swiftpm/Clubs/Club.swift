import Foundation

enum ClubType: String, Codable, CaseIterable, Identifiable {
    case driver
    case wood3
    case wood5
    case iron3
    case iron5
    case iron7
    case iron9
    case pitchingWedge
    case sandWedge
    case lobWedge
    case putter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .driver: return "Driver"
        case .wood3: return "3 Wood"
        case .wood5: return "5 Wood"
        case .iron3: return "3 Iron"
        case .iron5: return "5 Iron"
        case .iron7: return "7 Iron"
        case .iron9: return "9 Iron"
        case .pitchingWedge: return "Pitching Wedge"
        case .sandWedge: return "Sand Wedge"
        case .lobWedge: return "Lob Wedge"
        case .putter: return "Putter"
        }
    }

    var shortName: String {
        switch self {
        case .driver: return "DR"
        case .wood3: return "3W"
        case .wood5: return "5W"
        case .iron3: return "3i"
        case .iron5: return "5i"
        case .iron7: return "7i"
        case .iron9: return "9i"
        case .pitchingWedge: return "PW"
        case .sandWedge: return "SW"
        case .lobWedge: return "LW"
        case .putter: return "PT"
        }
    }

    /// Carry in yards for a club with power 50.
    var baseCarry: Double {
        switch self {
        case .driver: return 240
        case .wood3: return 220
        case .wood5: return 202
        case .iron3: return 188
        case .iron5: return 170
        case .iron7: return 150
        case .iron9: return 128
        case .pitchingWedge: return 110
        case .sandWedge: return 88
        case .lobWedge: return 68
        case .putter: return 36
        }
    }

    var launchAngle: Double {
        switch self {
        case .driver: return 13
        case .wood3: return 14.5
        case .wood5: return 16
        case .iron3: return 17
        case .iron5: return 19.5
        case .iron7: return 23
        case .iron9: return 29
        case .pitchingWedge: return 34
        case .sandWedge: return 41
        case .lobWedge: return 49
        case .putter: return 0
        }
    }

    /// Natural backspin of the club head design (0...1).
    var baseSpin: Double {
        switch self {
        case .driver: return 0.05
        case .wood3: return 0.10
        case .wood5: return 0.15
        case .iron3: return 0.22
        case .iron5: return 0.30
        case .iron7: return 0.40
        case .iron9: return 0.52
        case .pitchingWedge: return 0.60
        case .sandWedge: return 0.68
        case .lobWedge: return 0.74
        case .putter: return 0
        }
    }

    /// Typical roll after landing on fairway, as a fraction of carry (used by the aim advisor).
    var rollFraction: Double {
        switch self {
        case .driver: return 0.11
        case .wood3: return 0.10
        case .wood5: return 0.09
        case .iron3: return 0.08
        case .iron5: return 0.07
        case .iron7: return 0.06
        case .iron9: return 0.045
        case .pitchingWedge: return 0.035
        case .sandWedge: return 0.02
        case .lobWedge: return 0.015
        case .putter: return 0
        }
    }

    /// Maximum sideways curve (yards/s^2) for a badly timed swing.
    var curveStrength: Double {
        switch self {
        case .driver: return 2.4
        case .wood3, .wood5: return 2.1
        case .iron3, .iron5: return 1.8
        case .iron7, .iron9: return 1.5
        default: return 1.1
        }
    }

    var isPutter: Bool { self == .putter }
}

enum Rarity: Int, Codable, CaseIterable, Comparable, Identifiable {
    case common
    case uncommon
    case rare
    case epic
    case legendary

    var id: Int { rawValue }

    static func < (a: Rarity, b: Rarity) -> Bool { a.rawValue < b.rawValue }

    var displayName: String {
        switch self {
        case .common: return "Common"
        case .uncommon: return "Uncommon"
        case .rare: return "Rare"
        case .epic: return "Epic"
        case .legendary: return "Legendary"
        }
    }

    var color: RGBColor {
        switch self {
        case .common: return RGBColor(0.62, 0.66, 0.70)
        case .uncommon: return RGBColor(0.30, 0.75, 0.40)
        case .rare: return RGBColor(0.25, 0.55, 0.95)
        case .epic: return RGBColor(0.66, 0.36, 0.92)
        case .legendary: return RGBColor(0.98, 0.70, 0.16)
        }
    }

    var maxLevel: Int {
        switch self {
        case .common: return 6
        case .uncommon: return 7
        case .rare: return 8
        case .epic: return 9
        case .legendary: return 10
        }
    }
}

struct ClubStats: Codable, Equatable {
    var power: Double
    var accuracy: Double
    var forgiveness: Double
    var spin: Double
    var control: Double

    init(_ power: Double, _ accuracy: Double, _ forgiveness: Double, _ spin: Double, _ control: Double) {
        self.power = power
        self.accuracy = accuracy
        self.forgiveness = forgiveness
        self.spin = spin
        self.control = control
    }

    /// Stats after upgrades: every level adds a little to everything.
    func leveled(_ level: Int) -> ClubStats {
        let bonus = Double(max(0, level - 1)) * 1.6
        return ClubStats(
            min(100, power + bonus),
            min(100, accuracy + bonus),
            min(100, forgiveness + bonus),
            min(100, spin + bonus),
            min(100, control + bonus)
        )
    }
}

/// A platform-neutral colour. SwiftUI / SpriteKit conversions live in PlatformBridges.swift.
struct RGBColor: Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(hex: UInt32) {
        self.r = Double((hex >> 16) & 0xFF) / 255
        self.g = Double((hex >> 8) & 0xFF) / 255
        self.b = Double(hex & 0xFF) / 255
        self.a = 1
    }

    func shaded(_ f: Double) -> RGBColor {
        RGBColor(min(1, r * f), min(1, g * f), min(1, b * f), a)
    }

    func withAlpha(_ alpha: Double) -> RGBColor {
        RGBColor(r, g, b, alpha)
    }

    func mixed(with o: RGBColor, _ t: Double) -> RGBColor {
        RGBColor(lerpD(r, o.r, t), lerpD(g, o.g, t), lerpD(b, o.b, t), lerpD(a, o.a, t))
    }
}
