import Foundation

/// Every surface the ball can rest on or hit. Numbers are tuned for fun, not realism.
enum Terrain: String, Codable, CaseIterable {
    case tee
    case fairway
    case fringe
    case green
    case rough
    case heavyRough
    case sand
    case water
    case outOfBounds

    var displayName: String {
        switch self {
        case .tee: return "Tee"
        case .fairway: return "Fairway"
        case .fringe: return "Fringe"
        case .green: return "Green"
        case .rough: return "Rough"
        case .heavyRough: return "Heavy Rough"
        case .sand: return "Bunker"
        case .water: return "Water"
        case .outOfBounds: return "Out of Bounds"
        }
    }

    /// Fraction of a club's normal maximum distance available from this lie.
    var powerMultiplier: Double {
        switch self {
        case .tee, .fairway, .green: return 1.0
        case .fringe: return 0.96
        case .rough: return 0.84
        case .heavyRough: return 0.66
        case .sand: return 0.70
        case .water, .outOfBounds: return 1.0
        }
    }

    /// Scales the timing windows. Bad lies make the sweet spot smaller.
    var accuracyMultiplier: Double {
        switch self {
        case .tee, .fairway, .green: return 1.0
        case .fringe: return 0.95
        case .rough: return 0.82
        case .heavyRough: return 0.66
        case .sand: return 0.74
        case .water, .outOfBounds: return 1.0
        }
    }

    /// Vertical restitution when the ball lands here.
    var bounce: Double {
        switch self {
        case .tee, .fairway: return 0.32
        case .fringe: return 0.28
        case .green: return 0.24
        case .rough: return 0.18
        case .heavyRough: return 0.10
        case .sand: return 0.0
        case .water, .outOfBounds: return 0.0
        }
    }

    /// Fraction of horizontal speed kept on each bounce.
    var landingRetention: Double {
        switch self {
        case .tee, .fairway: return 0.50
        case .fringe: return 0.52
        case .green: return 0.55
        case .rough: return 0.40
        case .heavyRough: return 0.24
        case .sand: return 0.08
        case .water, .outOfBounds: return 0.0
        }
    }

    /// Rolling deceleration in yards / second^2.
    var rollFriction: Double {
        switch self {
        case .tee, .fairway: return 12.0
        case .fringe: return 4.6
        case .green: return 2.3
        case .rough: return 22.0
        case .heavyRough: return 40.0
        case .sand: return 70.0
        case .water, .outOfBounds: return 100.0
        }
    }

    var isPenalty: Bool { self == .water || self == .outOfBounds }
    var isPuttable: Bool { self == .green || self == .fringe }
}
