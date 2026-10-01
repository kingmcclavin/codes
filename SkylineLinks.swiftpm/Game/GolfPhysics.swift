import Foundation

/// Simplified arcade golf physics. Everything is in yards and seconds.
enum Physics {
    static let gravity = 9.0
    static let airDrag = 0.07
    static let windAccelPerMPH = 0.055
    static let cupRadius = 0.25
    static let cupCaptureSpeed = 3.8
    static let stepDt = 1.0 / 240.0
    static let maxSimTime = 40.0
    static let stopSpeed = 0.06
}

enum BallPhase {
    case flight
    case rolling
    case stopped
    case holed
    case water
    case outOfBounds

    var isFinished: Bool {
        switch self {
        case .flight, .rolling: return false
        default: return true
        }
    }
}

enum SimEvent {
    case landed(Terrain, Vec2)
    case treeHit(Vec2)
    case lipOut(Vec2)
    case holed(Vec2)
    case splash(Vec2)
    case outOfBounds(Vec2)
}

struct BallState {
    var pos: Vec2
    var z: Double
    var vel: Vec2
    var vz: Double
    /// 0...1, reduces forward bounce on the first landing.
    var backspin: Double
    /// Sideways acceleration in yards/s^2 while airborne. Positive curves right.
    var sideSpin: Double
    var phase: BallPhase
    var bounces: Int = 0
    var time: Double = 0
    var firstLanding: Vec2? = nil

    static func resting(at p: Vec2, ground: Double) -> BallState {
        BallState(pos: p, z: ground, vel: .zero, vz: 0, backspin: 0, sideSpin: 0, phase: .stopped)
    }
}

struct SimOptions {
    /// Wind acceleration vector (already scaled by club wind resistance).
    var windAccel: Vec2 = .zero
    var useSlope = true
    var useCup = true
    var useTrees = true
}

/// Steps the ball through flight, bounces and rolling on a specific hole.
struct BallSimulator {
    let hole: GolfHole
    var state: BallState
    var options: SimOptions
    private(set) var events: [SimEvent] = []

    init(hole: GolfHole, state: BallState, options: SimOptions) {
        self.hole = hole
        self.state = state
        self.options = options
    }

    var isFinished: Bool { state.phase.isFinished }

    /// Height of the ball above the ground under it.
    var heightAboveGround: Double {
        max(0, state.z - hole.groundHeight(at: state.pos))
    }

    mutating func popEvents() -> [SimEvent] {
        let e = events
        events.removeAll()
        return e
    }

    /// Advances by `dt` seconds using fixed sub-steps for stability.
    mutating func advance(_ dt: Double) {
        var remaining = dt
        while remaining > 1e-9 && !isFinished {
            let h = min(Physics.stepDt, remaining)
            step(h)
            remaining -= h
        }
    }

    mutating func runToEnd() {
        while !isFinished {
            step(Physics.stepDt)
        }
    }

    mutating func step(_ dt: Double) {
        state.time += dt
        if state.time > Physics.maxSimTime {
            state.phase = .stopped
            return
        }
        switch state.phase {
        case .flight: stepFlight(dt)
        case .rolling: stepRolling(dt)
        default: break
        }
    }

    // MARK: Flight

    private mutating func stepFlight(_ dt: Double) {
        var accel = options.windAccel - state.vel * Physics.airDrag
        if state.vel.length > 1 {
            accel += state.vel.normalized.rightPerp * state.sideSpin
        }
        state.vel += accel * dt
        state.vz -= (Physics.gravity + state.vz * Physics.airDrag) * dt
        state.pos += state.vel * dt
        state.z += state.vz * dt

        let ground = hole.groundHeight(at: state.pos)

        if options.useTrees {
            for tree in hole.decor where tree.blocking {
                if state.z - ground < tree.height && state.pos.distance(to: tree.position) < tree.radius {
                    let away = (state.pos - tree.position).normalized
                    state.pos = tree.position + away * (tree.radius + 0.3)
                    state.vel = away * (state.vel.length * 0.12)
                    state.vz = min(state.vz, 0) * 0.3
                    state.sideSpin = 0
                    events.append(.treeHit(state.pos))
                    break
                }
            }
        }

        if state.z <= ground && state.vz < 0 {
            state.z = ground
            land()
        }
    }

    private mutating func land() {
        let t = hole.terrain(at: state.pos)
        if state.firstLanding == nil { state.firstLanding = state.pos }
        if t == .water {
            state.phase = .water
            events.append(.splash(state.pos))
            return
        }
        if t == .outOfBounds {
            state.phase = .outOfBounds
            events.append(.outOfBounds(state.pos))
            return
        }
        events.append(.landed(t, state.pos))

        // A soft ball dropping straight onto the cup can go in.
        if options.useCup && state.pos.distance(to: hole.cup) < Physics.cupRadius * 1.4 && state.vel.length < 16 {
            state.pos = hole.cup
            state.phase = .holed
            events.append(.holed(hole.cup))
            return
        }

        state.bounces += 1
        // Steeper descents keep less forward speed; backspin bites on the first bounce.
        let descent = atan2(-state.vz, max(0.01, state.vel.length))
        var retention = t.landingRetention * (1 - 0.7 * sin(descent))
        if state.bounces == 1 {
            retention *= (1 - state.backspin * 0.9)
        }
        state.vel = state.vel * retention
        state.vz = -state.vz * t.bounce
        state.sideSpin = 0
        state.backspin *= 0.3
        if state.vz < 1.5 {
            state.vz = 0
            state.phase = .rolling
        }
    }

    // MARK: Rolling

    private mutating func stepRolling(_ dt: Double) {
        let t = hole.terrain(at: state.pos)
        if t == .water {
            state.phase = .water
            events.append(.splash(state.pos))
            return
        }
        if t == .outOfBounds {
            state.phase = .outOfBounds
            events.append(.outOfBounds(state.pos))
            return
        }

        let friction = hole.rollFriction(on: t)
        let speed = state.vel.length
        if speed > 0 {
            let drop = min(friction * dt, speed)
            state.vel = state.vel - state.vel / speed * drop
        }
        if options.useSlope && t.isPuttable {
            state.vel += hole.greenSlope * dt
        }
        state.pos += state.vel * dt
        state.z = hole.groundHeight(at: state.pos)

        if options.useTrees {
            for tree in hole.decor where tree.blocking {
                if state.pos.distance(to: tree.position) < tree.radius {
                    let away = (state.pos - tree.position).normalized
                    state.pos = tree.position + away * (tree.radius + 0.2)
                    state.vel = .zero
                    break
                }
            }
        }

        if options.useCup {
            let d = state.pos.distance(to: hole.cup)
            if d < Physics.cupRadius {
                let s = state.vel.length
                if s < Physics.cupCaptureSpeed {
                    state.pos = hole.cup
                    state.vel = .zero
                    state.phase = .holed
                    events.append(.holed(hole.cup))
                    return
                } else if s < Physics.cupCaptureSpeed * 1.8 && d < Physics.cupRadius * 0.85 {
                    // Lip out: the cup grabs the ball and spits it sideways.
                    let side = (state.pos - hole.cup).cross(state.vel) >= 0 ? -1.0 : 1.0
                    state.vel = state.vel.rotated(by: side * 0.7) * 0.45
                    state.pos = hole.cup + state.vel.normalized * (Physics.cupRadius + 0.02)
                    events.append(.lipOut(state.pos))
                }
            }
        }

        let slopePull = (options.useSlope && t.isPuttable) ? hole.greenSlope.length : 0
        if state.vel.length < Physics.stopSpeed && slopePull < friction * 0.6 {
            state.vel = .zero
            state.phase = .stopped
        }
    }

    // MARK: Tracing (used for previews and solving)

    struct Trace {
        var points: [Vec3]
        var landingIndex: Int?
        var finalState: BallState
    }

    /// Runs the simulation to completion, recording a point every `sampleEvery` seconds.
    static func trace(hole: GolfHole, start: BallState, options: SimOptions, sampleEvery: Double = 0.05, stopAtLanding: Bool = false) -> Trace {
        var sim = BallSimulator(hole: hole, state: start, options: options)
        var pts: [Vec3] = [Vec3(x: start.pos.x, y: start.pos.y, h: sim.heightAboveGround)]
        var landing: Int? = nil
        var acc = 0.0
        let dt = 1.0 / 120.0
        while !sim.isFinished {
            let wasFlying = sim.state.phase == .flight
            sim.step(dt)
            acc += dt
            let justLanded = wasFlying && sim.state.phase != .flight
            if acc >= sampleEvery || justLanded || sim.isFinished {
                acc = 0
                pts.append(Vec3(x: sim.state.pos.x, y: sim.state.pos.y, h: sim.heightAboveGround))
            }
            if justLanded && landing == nil {
                landing = pts.count - 1
                if stopAtLanding { break }
            }
        }
        return Trace(points: pts, landingIndex: landing, finalState: sim.state)
    }
}

// MARK: - Inverse problems: how hard must we hit it to land at a spot?

enum ShotSolver {
    static func launch(dir: Vec2, speed: Double, launchAngleDeg: Double) -> (Vec2, Double) {
        let a = degreesToRadians(launchAngleDeg)
        return (dir.normalized * (speed * cos(a)), speed * sin(a))
    }

    /// Where a shot first touches down (no wind, no curve, no trees).
    static func landingPoint(hole: GolfHole, from: Vec2, dir: Vec2, speed: Double, launchAngleDeg: Double) -> Vec2 {
        let (v, vz) = launch(dir: dir, speed: speed, launchAngleDeg: launchAngleDeg)
        let start = BallState(pos: from, z: hole.groundHeight(at: from), vel: v, vz: vz, backspin: 0, sideSpin: 0, phase: .flight)
        var opts = SimOptions()
        opts.useTrees = false
        opts.useCup = false
        var sim = BallSimulator(hole: hole, state: start, options: opts)
        let dt = 1.0 / 120.0
        while sim.state.phase == .flight && sim.state.time < 25 {
            sim.step(dt)
        }
        return sim.state.firstLanding ?? sim.state.pos
    }

    /// Carry distance on perfectly flat ground with no wind.
    static func flatCarry(speed: Double, launchAngleDeg: Double) -> Double {
        let (v, vz0) = launch(dir: Vec2(0, 1), speed: speed, launchAngleDeg: launchAngleDeg)
        var vel = v
        var vz = vz0
        var pos = Vec2.zero
        var z = 0.0
        let dt = 1.0 / 120.0
        var t = 0.0
        while t < 25 {
            vel += (Vec2.zero - vel * Physics.airDrag) * dt
            vz -= (Physics.gravity + vz * Physics.airDrag) * dt
            pos += vel * dt
            z += vz * dt
            t += dt
            if z <= 0 && vz < 0 { break }
        }
        return pos.length
    }

    private static var flatSpeedCache: [String: Double] = [:]

    static func flatSpeed(forCarry carry: Double, launchAngleDeg: Double) -> Double {
        let key = "\(Int((carry * 10).rounded()))-\(Int((launchAngleDeg * 10).rounded()))"
        if let cached = flatSpeedCache[key] { return cached }
        let v = solveFlatSpeed(carry: carry, launchAngleDeg: launchAngleDeg)
        flatSpeedCache[key] = v
        return v
    }

    private static func solveFlatSpeed(carry: Double, launchAngleDeg: Double) -> Double {
        var lo = 0.5
        var hi = 260.0
        for _ in 0..<32 {
            let mid = (lo + hi) / 2
            if flatCarry(speed: mid, launchAngleDeg: launchAngleDeg) < carry { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// Launch speed that lands `distance` yards along `dir` on this hole's terrain.
    static func speed(toCarry distance: Double, hole: GolfHole, from: Vec2, dir: Vec2, launchAngleDeg: Double) -> Double {
        var lo = 0.5
        var hi = 260.0
        for _ in 0..<26 {
            let mid = (lo + hi) / 2
            let land = landingPoint(hole: hole, from: from, dir: dir, speed: mid, launchAngleDeg: launchAngleDeg)
            if (land - from).dot(dir.normalized) < distance { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// Starting roll speed that stops a putt `distance` yards away, ignoring slope.
    static func puttSpeed(distance: Double, hole: GolfHole, from: Vec2, dir: Vec2) -> Double {
        var opts = SimOptions()
        opts.useSlope = false
        opts.useCup = false
        opts.useTrees = false
        var lo = 0.05
        var hi = 40.0
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            let start = BallState(pos: from, z: hole.groundHeight(at: from), vel: dir.normalized * mid, vz: 0, backspin: 0, sideSpin: 0, phase: .rolling)
            var sim = BallSimulator(hole: hole, state: start, options: opts)
            let dt = 1.0 / 120.0
            while !sim.isFinished && sim.state.time < 30 {
                sim.step(dt)
            }
            let travelled = (sim.state.pos - from).dot(dir.normalized)
            if travelled < distance { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }
}
