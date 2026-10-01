import Foundation

// MARK: - Geometry building blocks

enum AreaShape {
    case circle(center: Vec2, radius: Double)
    case ellipse(center: Vec2, rx: Double, ry: Double, rotation: Double)
    case rect(center: Vec2, width: Double, height: Double)

    func contains(_ p: Vec2) -> Bool {
        switch self {
        case let .circle(c, r):
            return p.distance(to: c) <= r
        case let .ellipse(c, rx, ry, rot):
            let local = (p - c).rotated(by: -rot)
            let nx = local.x / rx
            let ny = local.y / ry
            return nx * nx + ny * ny <= 1
        case let .rect(c, w, h):
            return abs(p.x - c.x) <= w / 2 && abs(p.y - c.y) <= h / 2
        }
    }

    var center: Vec2 {
        switch self {
        case let .circle(c, _): return c
        case let .ellipse(c, _, _, _): return c
        case let .rect(c, _, _): return c
        }
    }

    var boundingRadius: Double {
        switch self {
        case let .circle(_, r): return r
        case let .ellipse(_, rx, ry, _): return max(rx, ry)
        case let .rect(_, w, h): return (w * w + h * h).squareRoot() / 2
        }
    }

    /// The same shape grown outward by `m` yards (used for fringe around the green).
    func grown(by m: Double) -> AreaShape {
        switch self {
        case let .circle(c, r): return .circle(center: c, radius: r + m)
        case let .ellipse(c, rx, ry, rot): return .ellipse(center: c, rx: rx + m, ry: ry + m, rotation: rot)
        case let .rect(c, w, h): return .rect(center: c, width: w + 2 * m, height: h + 2 * m)
        }
    }
}

/// A fairway is a centre line with a width. Rough surrounds it by `roughWidth`.
struct FairwayStrip {
    var points: [Vec2]
    var width: Double

    func distance(to p: Vec2) -> Double {
        guard let first = points.first else { return Double.greatestFiniteMagnitude }
        if points.count == 1 { return p.distance(to: first) }
        var best = Double.greatestFiniteMagnitude
        for i in 0..<(points.count - 1) {
            best = min(best, segmentDistance(p, points[i], points[i + 1]))
        }
        return best
    }

    var length: Double {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for i in 0..<(points.count - 1) {
            total += points[i].distance(to: points[i + 1])
        }
        return total
    }

    /// Evenly spaced points along the centre line.
    func samples(every step: Double) -> [Vec2] {
        guard points.count > 1 else { return points }
        var result: [Vec2] = [points[0]]
        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            let seg = a.distance(to: b)
            let n = max(1, Int(seg / step))
            for k in 1...n {
                result.append(Vec2.lerp(a, b, Double(k) / Double(n)))
            }
        }
        return result
    }
}

struct Wind {
    /// Direction the wind blows TOWARD, radians in world space.
    var direction: Double
    var speedMPH: Double

    var vector: Vec2 { Vec2(angle: direction) * speedMPH }

    static let calm = Wind(direction: Double.pi / 2, speedMPH: 0)
}

/// Purely visual scenery. Trees (`blocking`) also stop low flying balls.
struct DecorItem {
    var position: Vec2
    var radius: Double
    var height: Double
    var blocking: Bool
    var variant: Int
}

enum HoleArchetype: String, CaseIterable {
    case straight
    case doglegLeft
    case doglegRight
    case waterCrossing
    case islandGreen
    case bunkerComplex
    case narrow
    case splitFairway
    case elevatedGreen
    case mountain
    case coastal

    var displayName: String {
        switch self {
        case .straight: return "Straightaway"
        case .doglegLeft: return "Dogleg Left"
        case .doglegRight: return "Dogleg Right"
        case .waterCrossing: return "Water Carry"
        case .islandGreen: return "Island Green"
        case .bunkerComplex: return "Bunker Maze"
        case .narrow: return "Tight Chute"
        case .splitFairway: return "Split Fairway"
        case .elevatedGreen: return "Elevated Green"
        case .mountain: return "Mountain Drop"
        case .coastal: return "Cliffside"
        }
    }
}

// MARK: - A complete hole (pure data, rendered by the scene, queried by physics)

struct GolfHole {
    let number: Int
    let name: String
    let par: Int
    let archetype: HoleArchetype
    let tee: Vec2
    let cup: Vec2
    let green: AreaShape
    let fringe: AreaShape
    let fairways: [FairwayStrip]
    let roughWidth: Double
    let bunkers: [AreaShape]
    let water: [AreaShape]
    let teeBox: AreaShape
    let bounds: WorldRect
    /// Height of the green above the tee in yards (negative = downhill hole).
    let greenElevation: Double
    /// Fraction of the tee-to-green distance where the elevation change begins.
    let elevationRampStart: Double
    /// Constant acceleration (yards/s^2) the green's slope applies to a rolling ball.
    let greenSlope: Vec2
    /// Multiplier on green friction (lower = faster greens).
    let greenSpeed: Double
    let wind: Wind
    /// Strokes the rival bot scored on this hole.
    let botStrokes: Int
    let decor: [DecorItem]

    var greenCenter: Vec2 { green.center }

    /// Yardage measured along the line of play.
    var yardage: Int {
        var points: [Vec2] = [tee]
        if par > 3, let main = fairways.max(by: { $0.length < $1.length }) {
            points.append(contentsOf: main.points)
        }
        points.append(cup)
        var total = 0.0
        for i in 0..<(points.count - 1) {
            total += points[i].distance(to: points[i + 1])
        }
        if par == 3 { total = tee.distance(to: cup) }
        return Int(total.rounded())
    }

    func terrain(at p: Vec2) -> Terrain {
        if teeBox.contains(p) { return .tee }
        if green.contains(p) { return .green }
        if fringe.contains(p) { return .fringe }
        for b in bunkers where b.contains(p) { return .sand }
        for w in water where w.contains(p) { return .water }
        if !bounds.contains(p) { return .outOfBounds }
        var nearest = Double.greatestFiniteMagnitude
        var nearestWidth = 0.0
        for f in fairways {
            let d = f.distance(to: p) - f.width / 2
            if d < nearest {
                nearest = d
                nearestWidth = f.width
            }
        }
        if nearest <= 0 { return .fairway }
        if nearest <= roughWidth && nearestWidth > 0 { return .rough }
        return .heavyRough
    }

    func groundHeight(at p: Vec2) -> Double {
        if greenElevation == 0 { return 0 }
        if fringe.grown(by: 6).contains(p) { return greenElevation }
        let axis = greenCenter - tee
        let l2 = axis.lengthSquared
        if l2 < 1 { return 0 }
        let t = ((p - tee).dot(axis) / l2).clamped(0, 1.2)
        let start = elevationRampStart
        let end = max(start + 0.05, 0.93)
        return greenElevation * smoothStepD(start, end, t)
    }

    func rollFriction(on t: Terrain) -> Double {
        if t == .green { return t.rollFriction * greenSpeed }
        return t.rollFriction
    }

    /// True when no tree stands on the straight line from `a` to `b`.
    func isPathClear(from a: Vec2, to b: Vec2) -> Bool {
        let ab = b - a
        let l2 = ab.lengthSquared
        if l2 < 1e-6 { return true }
        for tree in decor where tree.blocking {
            let t = (tree.position - a).dot(ab) / l2
            if t <= 0 { continue }
            let closest = a + ab * min(t, 1)
            if closest.distance(to: tree.position) < tree.radius + 0.5 { return false }
        }
        return true
    }

    /// Where to drop after the ball finished in water: walk back toward `from` until dry.
    func dropPoint(entry: Vec2, from: Vec2) -> Vec2 {
        let dir = (from - entry).normalized
        var p = entry
        for _ in 0..<200 {
            let t = terrain(at: p)
            if t != .water && t != .outOfBounds {
                let candidate = p + dir * 3
                let ct = terrain(at: candidate)
                return (ct == .water || ct == .outOfBounds) ? p : candidate
            }
            p = p + dir * 2
        }
        return from
    }
}
