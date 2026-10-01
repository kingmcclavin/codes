import Foundation

// MARK: - 2D vector (world units are yards)

struct Vec2: Equatable, Codable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    /// Unit vector pointing at `angle` radians (counter-clockwise from +x).
    init(angle: Double) {
        self.x = cos(angle)
        self.y = sin(angle)
    }

    static let zero = Vec2(0, 0)

    var length: Double { (x * x + y * y).squareRoot() }
    var lengthSquared: Double { x * x + y * y }
    var angle: Double { atan2(y, x) }

    var normalized: Vec2 {
        let l = length
        return l > 1e-9 ? Vec2(x / l, y / l) : Vec2.zero
    }

    /// Perpendicular pointing to the left of this direction.
    var leftPerp: Vec2 { Vec2(-y, x) }
    /// Perpendicular pointing to the right of this direction.
    var rightPerp: Vec2 { Vec2(y, -x) }

    func dot(_ o: Vec2) -> Double { x * o.x + y * o.y }
    func cross(_ o: Vec2) -> Double { x * o.y - y * o.x }
    func distance(to o: Vec2) -> Double { (self - o).length }

    func rotated(by a: Double) -> Vec2 {
        let c = cos(a)
        let s = sin(a)
        return Vec2(x * c - y * s, x * s + y * c)
    }

    static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    static func * (s: Double, a: Vec2) -> Vec2 { Vec2(a.x * s, a.y * s) }
    static func / (a: Vec2, s: Double) -> Vec2 { Vec2(a.x / s, a.y / s) }
    static prefix func - (a: Vec2) -> Vec2 { Vec2(-a.x, -a.y) }
    static func += (a: inout Vec2, b: Vec2) { a = a + b }
    static func -= (a: inout Vec2, b: Vec2) { a = a - b }

    static func lerp(_ a: Vec2, _ b: Vec2, _ t: Double) -> Vec2 {
        Vec2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
    }
}

/// A point on the ground plus a height above that ground (used for drawing ball flight).
struct Vec3 {
    var x: Double
    var y: Double
    var h: Double

    var ground: Vec2 { Vec2(x, y) }
}

struct WorldRect {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
    var center: Vec2 { Vec2((minX + maxX) / 2, (minY + maxY) / 2) }

    func contains(_ p: Vec2) -> Bool {
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }

    func expanded(by m: Double) -> WorldRect {
        WorldRect(minX: minX - m, minY: minY - m, maxX: maxX + m, maxY: maxY + m)
    }
}

// MARK: - Small numeric helpers (named to avoid clashing with simd / SwiftUI symbols)

extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self {
        min(max(self, lo), hi)
    }
}

func lerpD(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

func smoothStepD(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
    if e1 <= e0 { return x >= e1 ? 1 : 0 }
    let t = ((x - e0) / (e1 - e0)).clamped(0, 1)
    return t * t * (3 - 2 * t)
}

func degreesToRadians(_ d: Double) -> Double { d * Double.pi / 180 }

/// Shortest signed difference between two angles, in (-pi, pi].
func angleDelta(from a: Double, to b: Double) -> Double {
    var d = (b - a).truncatingRemainder(dividingBy: 2 * Double.pi)
    if d > Double.pi { d -= 2 * Double.pi }
    if d < -Double.pi { d += 2 * Double.pi }
    return d
}

/// Distance from point p to the segment a-b.
func segmentDistance(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
    let ab = b - a
    let l2 = ab.lengthSquared
    if l2 < 1e-9 { return p.distance(to: a) }
    let t = ((p - a).dot(ab) / l2).clamped(0, 1)
    return p.distance(to: a + ab * t)
}

// MARK: - Deterministic random numbers (so generated courses are identical every launch)

struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func range(_ a: Double, _ b: Double) -> Double {
        if b <= a { return a }
        return Double.random(in: a...b, using: &self)
    }

    mutating func int(_ a: Int, _ b: Int) -> Int {
        if b <= a { return a }
        return Int.random(in: a...b, using: &self)
    }

    mutating func chance(_ p: Double) -> Bool {
        range(0, 1) < p
    }

    mutating func sign() -> Double {
        chance(0.5) ? 1 : -1
    }

    mutating func pick<T>(_ items: [T]) -> T {
        items[int(0, items.count - 1)]
    }

    /// Roughly normal distribution in about [-1, 1] (sum of three uniforms).
    mutating func bell() -> Double {
        (range(-1, 1) + range(-1, 1) + range(-1, 1)) / 3
    }
}
