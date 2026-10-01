import Foundation

/// Data-driven ability effects. Add a case here, describe it, and apply it in `ShotModifiers.make`.
enum AbilityKind: String, Codable {
    /// Recovers a percentage of the distance AND accuracy lost from a bad lie (rough, heavy rough, sand).
    case lieRecovery
    /// Extra distance (in %) when hitting from the fairway or tee.
    case fairwayPower
    /// Widens all timing windows by %.
    case forgiveness
    /// Reduces shot spray by %.
    case accuracy
    /// Reduces wind effect by %.
    case windResistance
    /// Increases maximum distance by %.
    case distance
    /// Accuracy bonus (%) when the target is under `threshold` yards.
    case shortGameAccuracy
    /// Extra backspin (%), so the ball stops faster.
    case backspin
    /// Reduces putt error (%) and reveals more of the putt preview.
    case puttingAccuracy
}

struct ClubAbility: Codable, Equatable {
    var kind: AbilityKind
    var name: String
    /// Value at level 1, in percent.
    var baseValue: Double
    /// Added per upgrade level.
    var perLevel: Double
    /// For `lieRecovery`: which lie it applies to.
    var terrain: Terrain? = nil
    /// For `shortGameAccuracy`: yards.
    var threshold: Double? = nil

    func value(at level: Int) -> Double {
        baseValue + perLevel * Double(max(0, level - 1))
    }

    func describe(level: Int) -> String {
        let v = Int(value(at: level).rounded())
        switch kind {
        case .lieRecovery:
            return "+\(v)% Power from \(terrain?.displayName ?? "Rough")"
        case .fairwayPower:
            return "+\(v)% Distance from Fairway & Tee"
        case .forgiveness:
            return "+\(v)% Forgiveness"
        case .accuracy:
            return "+\(v)% Accuracy"
        case .windResistance:
            return "-\(v)% Wind Effect"
        case .distance:
            return "+\(v)% Maximum Distance"
        case .shortGameAccuracy:
            return "+\(v)% Accuracy Under \(Int(threshold ?? 150)) Yards"
        case .backspin:
            return "+\(v)% Backspin"
        case .puttingAccuracy:
            return "+\(v)% Putting Accuracy"
        }
    }

    // Convenience constructors keep the catalog readable.
    static func lie(_ name: String, _ t: Terrain, _ base: Double, _ per: Double = 5) -> ClubAbility {
        ClubAbility(kind: .lieRecovery, name: name, baseValue: base, perLevel: per, terrain: t)
    }
    static func fairway(_ name: String, _ base: Double, _ per: Double = 0.5) -> ClubAbility {
        ClubAbility(kind: .fairwayPower, name: name, baseValue: base, perLevel: per)
    }
    static func forgive(_ name: String, _ base: Double, _ per: Double = 4) -> ClubAbility {
        ClubAbility(kind: .forgiveness, name: name, baseValue: base, perLevel: per)
    }
    static func accurate(_ name: String, _ base: Double, _ per: Double = 3) -> ClubAbility {
        ClubAbility(kind: .accuracy, name: name, baseValue: base, perLevel: per)
    }
    static func wind(_ name: String, _ base: Double, _ per: Double = 4) -> ClubAbility {
        ClubAbility(kind: .windResistance, name: name, baseValue: base, perLevel: per)
    }
    static func distance(_ name: String, _ base: Double, _ per: Double = 0.5) -> ClubAbility {
        ClubAbility(kind: .distance, name: name, baseValue: base, perLevel: per)
    }
    static func shortGame(_ name: String, _ base: Double, _ under: Double = 150, _ per: Double = 4) -> ClubAbility {
        ClubAbility(kind: .shortGameAccuracy, name: name, baseValue: base, perLevel: per, threshold: under)
    }
    static func spin(_ name: String, _ base: Double, _ per: Double = 5) -> ClubAbility {
        ClubAbility(kind: .backspin, name: name, baseValue: base, perLevel: per)
    }
    static func putting(_ name: String, _ base: Double, _ per: Double = 5) -> ClubAbility {
        ClubAbility(kind: .puttingAccuracy, name: name, baseValue: base, perLevel: per)
    }
}

/// Everything about a shot that a club's stats + abilities + lie change.
struct ShotModifiers {
    /// Multiplier on the club's maximum carry.
    var reachMultiplier: Double = 1
    /// Multiplier on timing window size (bigger = easier).
    var windowMultiplier: Double = 1
    /// Multiplier on directional error (smaller = straighter).
    var sprayMultiplier: Double = 1
    /// Multiplier on wind acceleration.
    var windFactor: Double = 1
    /// Final backspin, 0...0.95.
    var backspin: Double = 0
    /// Multiplier on putt error.
    var puttErrorMultiplier: Double = 1
    /// Fraction of the putt preview line that is shown.
    var puttPreviewFraction: Double = 0.4
}

/// A club card as it sits in the player's bag: definition + level.
struct EquippedClub {
    let card: ClubCardDefinition
    let level: Int

    var type: ClubType { card.type }
    var stats: ClubStats { card.stats.leveled(level) }

    /// Maximum carry in yards from a perfect lie with no ability bonus.
    var carry: Double {
        if type.isPutter { return 30 + stats.power * 0.2 }
        return type.baseCarry * (0.88 + stats.power / 100 * 0.24)
    }

    func abilityValue(_ kind: AbilityKind) -> Double {
        card.abilities.filter { $0.kind == kind }.reduce(0) { $0 + $1.value(at: level) }
    }

    func modifiers(lie: Terrain, targetDistance: Double) -> ShotModifiers {
        var m = ShotModifiers()
        let s = stats

        // Lie penalties, partly recovered by matching lie abilities.
        var power = lie.powerMultiplier
        var acc = lie.accuracyMultiplier
        let recovery = card.abilities
            .filter { $0.kind == .lieRecovery && $0.terrain == lie }
            .reduce(0.0) { $0 + $1.value(at: level) }
        if recovery > 0 {
            let r = min(recovery, 100) / 100
            power += (1 - power) * r
            acc += (1 - acc) * r * 0.6
        }
        if lie == .fairway || lie == .tee {
            power *= 1 + abilityValue(.fairwayPower) / 100
        }
        power *= 1 + abilityValue(.distance) / 100
        m.reachMultiplier = power

        let forgive = abilityValue(.forgiveness)
        m.windowMultiplier = acc * (1 + forgive / 100)

        var accuracyBonus = abilityValue(.accuracy)
        let shortGame = card.abilities.filter { $0.kind == .shortGameAccuracy }
        for a in shortGame where targetDistance <= (a.threshold ?? 150) {
            accuracyBonus += a.value(at: level)
        }
        m.sprayMultiplier = (1 / (1 + accuracyBonus / 100)) / max(0.5, acc)

        m.windFactor = max(0.1, 1 - abilityValue(.windResistance) / 100)

        let spinStat = 0.6 + s.spin / 100 * 0.8
        let spinBonus = 1 + abilityValue(.backspin) / 100
        m.backspin = (type.baseSpin * spinStat * spinBonus).clamped(0, 0.95)

        let puttBonus = abilityValue(.puttingAccuracy)
        m.puttErrorMultiplier = 1 / (1 + puttBonus / 100)
        m.puttPreviewFraction = (0.35 + s.accuracy / 100 * 0.1 + puttBonus / 100 * 0.25).clamped(0.3, 0.8)
        return m
    }

    /// Meter speed multiplier; better control = slower, easier meter.
    var meterSpeed: Double {
        1.18 - stats.control / 100 * 0.36
    }
}
