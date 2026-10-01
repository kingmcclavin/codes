import Foundation

enum SwingOutcome: String {
    case perfect
    case great
    case good
    case early
    case late
    case poor

    var title: String {
        switch self {
        case .perfect: return "PERFECT!"
        case .great: return "GREAT"
        case .good: return "GOOD"
        case .early: return "EARLY"
        case .late: return "LATE"
        case .poor: return "POOR"
        }
    }

    /// Multiplier on intended distance.
    var powerFactor: Double {
        switch self {
        case .perfect: return 1.0
        case .great: return 0.985
        case .good: return 0.96
        case .early, .late: return 0.9
        case .poor: return 0.72
        }
    }

    /// Multiplier on timing-based direction error.
    var sprayScale: Double {
        switch self {
        case .perfect: return 0
        case .great: return 0.8
        case .good: return 1.0
        case .early, .late: return 1.15
        case .poor: return 1.4
        }
    }
}

/// Half-widths of each zone on the accuracy bar, which runs from -1 (early) to +1 (late).
struct TimingWindows {
    var perfect: Double
    var great: Double
    var good: Double
    var edge: Double = 0.72

    static func make(forgiveness: Double, multiplier: Double) -> TimingWindows {
        let base = 0.045 + forgiveness / 100 * 0.075
        let p = (base * multiplier).clamped(0.02, 0.22)
        return TimingWindows(perfect: p, great: min(p * 2.2, 0.45), good: min(p * 3.8, 0.62))
    }

    func classify(_ offset: Double) -> SwingOutcome {
        let a = abs(offset)
        if a <= perfect { return .perfect }
        if a <= great { return .great }
        if a <= good { return .good }
        if a <= edge { return offset < 0 ? .early : .late }
        return .poor
    }
}

/// The three-step swing: hold to build power, release to lock it, tap as the needle crosses the sweet spot.
/// Putts only use the power step.
struct SwingMeterState {
    enum Phase {
        case idle
        case charging
        case accuracy
        case finished
    }

    enum Event {
        case none
        case cancelled
        case powerLocked
        case completed(power: Double, offset: Double?)
    }

    static let maxPower = 1.1
    static let needleStart = -1.05
    static let needleEnd = 1.25

    var phase: Phase = .idle
    var power: Double = 0
    var lockedPower: Double = 0
    var needle: Double = SwingMeterState.needleStart
    var isPutt = false
    /// 1.0 is normal speed; club control lowers it.
    var speed: Double = 1
    private var direction: Double = 1

    var powerRate: Double { (isPutt ? 0.75 : 0.9) * speed }
    var needleRate: Double { 2.5 * speed }

    mutating func reset() {
        phase = .idle
        power = 0
        lockedPower = 0
        needle = SwingMeterState.needleStart
        direction = 1
    }

    mutating func touchDown() -> Event {
        switch phase {
        case .idle:
            phase = .charging
            power = 0
            direction = 1
            return .none
        case .accuracy:
            phase = .finished
            return .completed(power: lockedPower, offset: needle)
        default:
            return .none
        }
    }

    mutating func touchUp() -> Event {
        guard phase == .charging else { return .none }
        if power < 0.03 {
            reset()
            return .cancelled
        }
        lockedPower = power
        if isPutt {
            phase = .finished
            return .completed(power: lockedPower, offset: nil)
        }
        phase = .accuracy
        needle = SwingMeterState.needleStart
        return .powerLocked
    }

    mutating func tick(_ dt: Double) -> Event {
        switch phase {
        case .charging:
            power += powerRate * direction * dt
            if power >= SwingMeterState.maxPower {
                power = SwingMeterState.maxPower
                direction = -1
            }
            if power <= 0 && direction < 0 {
                reset()
                return .cancelled
            }
            return .none
        case .accuracy:
            needle += needleRate * dt
            if needle >= SwingMeterState.needleEnd {
                phase = .finished
                return .completed(power: lockedPower, offset: needle)
            }
            return .none
        default:
            return .none
        }
    }
}

/// Everything needed to start the ball moving.
struct ShotLaunch {
    var state: BallState
    var options: SimOptions
    var outcome: SwingOutcome?
}

enum ShotPlanner {
    static func fullSwing(club: EquippedClub, lie: Terrain, hole: GolfHole, from: Vec2, target: Vec2,
                          power: Double, offset: Double, rng: inout SeededRandom) -> ShotLaunch {
        let toTarget = target - from
        let dir = toTarget.normalized
        let distance = toTarget.length
        let mods = club.modifiers(lie: lie, targetDistance: distance)
        let windows = TimingWindows.make(forgiveness: club.stats.forgiveness, multiplier: mods.windowMultiplier)
        let outcome = windows.classify(offset)
        let o = offset.clamped(-1.2, 1.2)

        let needed = ShotSolver.speed(toCarry: distance, hole: hole, from: from, dir: dir, launchAngleDeg: club.type.launchAngle)
        let distanceScale = max(0.05, power * outcome.powerFactor)
        let speed = needed * distanceScale.squareRoot()

        let accuracy = club.stats.accuracy
        let spray = degreesToRadians(8) * (1.35 - accuracy / 100 * 0.85) * mods.sprayMultiplier
        // Early (negative offset) pulls left (positive rotation), late pushes right.
        var angleError = -o * spray * outcome.sprayScale
        let scatterScale = outcome == .perfect ? 0.2 : 1.0
        angleError += rng.bell() * degreesToRadians(1.2) * (1.25 - accuracy / 100) * mods.sprayMultiplier * scatterScale
        if power > 1.0 {
            // Overswing: more distance but harder to control.
            angleError += rng.bell() * degreesToRadians(30) * (power - 1.0)
        }
        var sideSpin = 0.0
        if outcome != .perfect {
            sideSpin = o * club.type.curveStrength * (1.25 - accuracy / 100 * 0.6) * mods.sprayMultiplier
        }

        let launchDir = dir.rotated(by: angleError)
        let (v, vz) = ShotSolver.launch(dir: launchDir, speed: speed, launchAngleDeg: club.type.launchAngle)
        let state = BallState(pos: from, z: hole.groundHeight(at: from), vel: v, vz: vz,
                              backspin: mods.backspin, sideSpin: sideSpin, phase: .flight)
        var opts = SimOptions()
        opts.windAccel = hole.wind.vector * (Physics.windAccelPerMPH * mods.windFactor)
        return ShotLaunch(state: state, options: opts, outcome: outcome)
    }

    static func putt(club: EquippedClub, lie: Terrain, hole: GolfHole, from: Vec2, target: Vec2,
                     power: Double, rng: inout SeededRandom) -> ShotLaunch {
        let toTarget = target - from
        let dir = toTarget.normalized
        let mods = club.modifiers(lie: lie, targetDistance: toTarget.length)
        let needed = ShotSolver.puttSpeed(distance: toTarget.length, hole: hole, from: from, dir: dir)
        let speed = needed * max(0.02, power).squareRoot()
        let errorDeg = 1.5 * (1.3 - club.stats.accuracy / 100) * mods.puttErrorMultiplier
        let angleError = rng.bell() * degreesToRadians(errorDeg)
        let state = BallState(pos: from, z: hole.groundHeight(at: from), vel: dir.rotated(by: angleError) * speed,
                              vz: 0, backspin: 0, sideSpin: 0, phase: .rolling)
        return ShotLaunch(state: state, options: SimOptions(), outcome: nil)
    }

    /// Outcome rating for a putt, based only on power accuracy.
    static func puttRating(power: Double) -> String {
        let e = abs(power - 1)
        if e < 0.03 { return "PURE" }
        if e < 0.08 { return "SOLID" }
        return power > 1 ? "FIRM" : "SOFT"
    }
}

/// Picks a sensible club and target before each shot so the player can just swing if they want.
enum ShotAdvisor {
    /// Maximum reach (first landing distance) for a club in a direction from the current lie.
    static func reach(club: EquippedClub, lie: Terrain, hole: GolfHole, from: Vec2, dir: Vec2) -> Double {
        if club.type.isPutter { return club.carry }
        let mods = club.modifiers(lie: lie, targetDistance: 200)
        let flatCarry = club.carry * mods.reachMultiplier
        let speed = ShotSolver.flatSpeed(forCarry: flatCarry, launchAngleDeg: club.type.launchAngle)
        let land = ShotSolver.landingPoint(hole: hole, from: from, dir: dir, speed: speed, launchAngleDeg: club.type.launchAngle)
        return max(5, (land - from).dot(dir.normalized))
    }

    static func clampTarget(_ target: Vec2, club: EquippedClub, lie: Terrain, hole: GolfHole, from: Vec2) -> Vec2 {
        var t = target
        var d = t - from
        if d.length < 0.05 {
            d = (hole.cup - from).normalized * 5
            if d.length < 0.05 { d = Vec2(0, 5) }
            t = from + d
        }
        let dir = d.normalized
        let maxD = reach(club: club, lie: lie, hole: hole, from: from, dir: dir)
        let minD = club.type.isPutter ? 0.2 : 3.0
        let len = d.length.clamped(minD, max(minD, maxD))
        return from + dir * len
    }

    static func estimatedRoll(club: EquippedClub, distance: Double) -> Double {
        club.type.rollFraction * distance
    }

    private static func isGoodRest(_ t: Terrain) -> Bool {
        t == .fairway || t == .fringe || t == .green
    }

    /// Best aim point for a club: just short of the cup if reachable (so the ball releases to it),
    /// otherwise the fairway spot that leaves the shortest next shot with a clear line and a safe roll.
    static func defaultTarget(club: EquippedClub, lie: Terrain, hole: GolfHole, from: Vec2) -> Vec2 {
        let toCup = hole.cup - from
        if club.type.isPutter {
            return clampTarget(hole.cup, club: club, lie: lie, hole: hole, from: from)
        }
        let cupReach = reach(club: club, lie: lie, hole: hole, from: from, dir: toCup)
        if cupReach >= toCup.length * 0.98 && hole.isPathClear(from: from, to: hole.cup) {
            let roll = estimatedRoll(club: club, distance: toCup.length)
            var t = hole.cup - toCup.normalized * roll
            if !isGoodRest(hole.terrain(at: t)) {
                t = hole.cup - toCup.normalized * (roll * 0.4)
            }
            return clampTarget(t, club: club, lie: lie, hole: hole, from: from)
        }

        let flatReach = club.carry * club.modifiers(lie: lie, targetDistance: 200).reachMultiplier
        var samples: [Vec2] = []
        for strip in hole.fairways {
            samples.append(contentsOf: strip.samples(every: 6))
        }
        // Pass 1: land on fairway, finish on fairway/green, clear line. Pass 2: any clear line forward.
        for strict in [true, false] {
            var best: Vec2? = nil
            var bestScore = Double.greatestFiniteMagnitude
            for p in samples {
                let d = p.distance(to: from)
                if d > flatReach * 0.97 || d < (strict ? 15 : 5) { continue }
                let dir = (p - from) / d
                let rest = p + dir * estimatedRoll(club: club, distance: d)
                if strict {
                    if hole.terrain(at: p) != .fairway { continue }
                    if !isGoodRest(hole.terrain(at: rest)) { continue }
                }
                if !hole.isPathClear(from: from, to: p) { continue }
                let score = rest.distance(to: hole.cup)
                if score < bestScore {
                    bestScore = score
                    best = p
                }
            }
            if let b = best, bestScore < toCup.length {
                return clampTarget(b, club: club, lie: lie, hole: hole, from: from)
            }
        }
        return clampTarget(from + toCup.normalized * min(cupReach, toCup.length), club: club, lie: lie, hole: hole, from: from)
    }

    /// The club the advisor suggests for this situation.
    static func suggestClub(bag: [ClubType: EquippedClub], lie: Terrain, hole: GolfHole, from: Vec2) -> ClubType {
        let distance = from.distance(to: hole.cup)
        if lie == .green || (lie == .fringe && distance < 22) {
            return .putter
        }
        let ordered = ClubType.allCases.filter { $0 != .putter && bag[$0] != nil }.reversed()
        // Shortest club that can reach the cup (with a little roll allowance).
        for type in ordered {
            guard let club = bag[type] else { continue }
            if type == .driver && lie != .tee { continue }
            let mods = club.modifiers(lie: lie, targetDistance: distance)
            if club.carry * mods.reachMultiplier >= distance * 0.97 {
                return type
            }
        }
        if lie == .tee { return .driver }
        return bag[.wood3] != nil ? .wood3 : .driver
    }
}

/// Golf scoring vocabulary.
enum ScoreName {
    static func name(strokes: Int, par: Int) -> String {
        if strokes == 1 { return "HOLE IN ONE!" }
        switch strokes - par {
        case ...(-3): return "ALBATROSS!"
        case -2: return "EAGLE!"
        case -1: return "BIRDIE!"
        case 0: return "PAR"
        case 1: return "BOGEY"
        case 2: return "DOUBLE BOGEY"
        case 3: return "TRIPLE BOGEY"
        default: return "+\(strokes - par)"
        }
    }

    static func toParString(_ v: Int) -> String {
        if v == 0 { return "E" }
        return v > 0 ? "+\(v)" : "\(v)"
    }

    /// Hole ends automatically at this many strokes.
    static func maxStrokes(par: Int) -> Int { par + 4 }
}
