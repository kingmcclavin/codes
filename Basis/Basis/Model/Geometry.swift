import CoreGraphics
import Foundation

// MARK: - Vector arithmetic on CGPoint

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    static func / (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x / s, y: a.y / s) }
    static prefix func - (a: CGPoint) -> CGPoint { CGPoint(x: -a.x, y: -a.y) }
    static func += (a: inout CGPoint, b: CGPoint) { a = a + b }

    var length: CGFloat { (x * x + y * y).squareRoot() }
    var lengthSquared: CGFloat { x * x + y * y }

    var normalized: CGPoint {
        let l = length
        return l > 1e-9 ? CGPoint(x: x / l, y: y / l) : .zero
    }

    /// Rotated 90° counter-clockwise (in a y-up frame).
    var perpendicular: CGPoint { CGPoint(x: -y, y: x) }

    var angle: CGFloat { atan2(y, x) }

    func distance(to p: CGPoint) -> CGFloat { (self - p).length }
    func distanceSquared(to p: CGPoint) -> CGFloat { (self - p).lengthSquared }
    func dot(_ p: CGPoint) -> CGFloat { x * p.x + y * p.y }
    func cross(_ p: CGPoint) -> CGFloat { x * p.y - y * p.x }
    func lerp(to p: CGPoint, t: CGFloat) -> CGPoint { self + (p - self) * t }
    func midpoint(_ p: CGPoint) -> CGPoint { CGPoint(x: (x + p.x) * 0.5, y: (y + p.y) * 0.5) }

    func rotated(by angle: CGFloat, around c: CGPoint = .zero) -> CGPoint {
        let s = sin(angle), co = cos(angle)
        let d = self - c
        return CGPoint(x: c.x + d.x * co - d.y * s, y: c.y + d.x * s + d.y * co)
    }

    static func unit(angle: CGFloat) -> CGPoint { CGPoint(x: cos(angle), y: sin(angle)) }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }

    func expanded(by d: CGFloat) -> CGRect { insetBy(dx: -d, dy: -d) }

    var diagonal: CGFloat { (width * width + height * height).squareRoot() }

    static func bounding(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            if p.x < minX { minX = p.x } else if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y } else if p.y > maxY { maxY = p.y }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    var corners: [CGPoint] {
        [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY),
         CGPoint(x: maxX, y: maxY), CGPoint(x: minX, y: maxY)]
    }
}

extension CGAffineTransform {
    /// Geometric-mean scale factor; used to scale stroke widths under a transform.
    var scaleFactor: CGFloat { abs(a * d - b * c).squareRoot() }

    /// Rotation component (angle of the transformed x axis).
    var rotationAngle: CGFloat { atan2(b, a) }

    func applyToVector(_ v: CGPoint) -> CGPoint {
        CGPoint(x: a * v.x + c * v.y, y: b * v.x + d * v.y)
    }
}

extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}

// MARK: - Computational geometry helpers

enum Geometry {
    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = b - a
        let len2 = ab.lengthSquared
        if len2 < 1e-12 { return p.distance(to: a) }
        let t = ((p - a).dot(ab) / len2).clamped(0, 1)
        return p.distance(to: a + ab * t)
    }

    static func distance(from p: CGPoint, toPolyline pts: [CGPoint]) -> CGFloat {
        guard let first = pts.first else { return .greatestFiniteMagnitude }
        if pts.count == 1 { return p.distance(to: first) }
        var best = CGFloat.greatestFiniteMagnitude
        for i in 1..<pts.count {
            best = min(best, distance(from: p, toSegment: pts[i - 1], pts[i]))
        }
        return best
    }

    /// Minimum distance between two segments.
    static func distance(segment a1: CGPoint, _ a2: CGPoint, segment b1: CGPoint, _ b2: CGPoint) -> CGFloat {
        if segmentsIntersect(a1, a2, b1, b2) { return 0 }
        return min(distance(from: a1, toSegment: b1, b2), distance(from: a2, toSegment: b1, b2),
                   distance(from: b1, toSegment: a1, a2), distance(from: b2, toSegment: a1, a2))
    }

    static func segmentsIntersect(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ p4: CGPoint) -> Bool {
        let d1 = (p4 - p3).cross(p1 - p3)
        let d2 = (p4 - p3).cross(p2 - p3)
        let d3 = (p2 - p1).cross(p3 - p1)
        let d4 = (p2 - p1).cross(p4 - p1)
        return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }

    static func pathLength(_ pts: [CGPoint]) -> CGFloat {
        guard pts.count > 1 else { return 0 }
        var l: CGFloat = 0
        for i in 1..<pts.count { l += pts[i].distance(to: pts[i - 1]) }
        return l
    }

    /// Resamples a polyline to `count` evenly spaced points.
    static func resample(_ pts: [CGPoint], count n: Int) -> [CGPoint] {
        guard pts.count > 1, n > 1 else { return pts }
        let total = pathLength(pts)
        guard total > 1e-6 else { return Array(repeating: pts[0], count: n) }
        return resample(pts, spacing: total / CGFloat(n - 1), maxCount: n)
    }

    static func resample(_ pts: [CGPoint], spacing: CGFloat, maxCount: Int = .max) -> [CGPoint] {
        guard pts.count > 1, spacing > 0 else { return pts }
        var result = [pts[0]]
        var carried: CGFloat = 0
        var prev = pts[0]
        var i = 1
        while i < pts.count {
            let cur = pts[i]
            let d = prev.distance(to: cur)
            if carried + d >= spacing, d > 0 {
                let t = (spacing - carried) / d
                let q = prev.lerp(to: cur, t: t)
                result.append(q)
                if result.count >= maxCount { return result }
                prev = q
                carried = 0
            } else {
                carried += d
                prev = cur
                i += 1
            }
        }
        if result.count < maxCount, let last = pts.last, result.last.map({ $0.distance(to: last) > spacing * 0.01 }) ?? true {
            result.append(last)
        }
        return result
    }

    static func polygonContains(_ poly: [CGPoint], _ p: CGPoint) -> Bool {
        guard poly.count >= 3 else { return false }
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y) {
                let x = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    static func polygonArea(_ poly: [CGPoint]) -> CGFloat {
        guard poly.count >= 3 else { return 0 }
        var a: CGFloat = 0
        for i in 0..<poly.count {
            a += poly[i].cross(poly[(i + 1) % poly.count])
        }
        return a * 0.5
    }

    static func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        let pts = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard pts.count > 2 else { return pts }
        var lower: [CGPoint] = []
        for p in pts {
            while lower.count >= 2, (lower[lower.count - 1] - lower[lower.count - 2]).cross(p - lower[lower.count - 2]) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }
        var upper: [CGPoint] = []
        for p in pts.reversed() {
            while upper.count >= 2, (upper[upper.count - 1] - upper[upper.count - 2]).cross(p - upper[upper.count - 2]) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }
        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }

    struct PrincipalAxes {
        var centroid: CGPoint
        var major: CGPoint      // unit vector
        var minor: CGPoint      // unit vector
        var majorVariance: CGFloat
        var minorVariance: CGFloat
    }

    static func principalAxes(_ pts: [CGPoint]) -> PrincipalAxes {
        let n = CGFloat(max(pts.count, 1))
        var c = CGPoint.zero
        for p in pts { c += p }
        c = c / n
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        for p in pts {
            let d = p - c
            sxx += d.x * d.x; syy += d.y * d.y; sxy += d.x * d.y
        }
        sxx /= n; syy /= n; sxy /= n
        let theta = 0.5 * atan2(2 * sxy, sxx - syy)
        let major = CGPoint.unit(angle: theta)
        let tr = sxx + syy
        let det = sxx * syy - sxy * sxy
        let disc = max(0, tr * tr / 4 - det).squareRoot()
        return PrincipalAxes(centroid: c, major: major, minor: major.perpendicular,
                             majorVariance: tr / 2 + disc, minorVariance: max(0, tr / 2 - disc))
    }

    /// Total-least-squares line fit. Returns a point on the line and a unit direction.
    static func fitLine(_ pts: [CGPoint]) -> (point: CGPoint, direction: CGPoint) {
        let axes = principalAxes(pts)
        return (axes.centroid, axes.major)
    }

    static func lineIntersection(_ p1: CGPoint, _ d1: CGPoint, _ p2: CGPoint, _ d2: CGPoint) -> CGPoint? {
        let denom = d1.cross(d2)
        if abs(denom) < 1e-9 { return nil }
        let t = (p2 - p1).cross(d2) / denom
        return p1 + d1 * t
    }

    /// Smallest angle difference between two angles, in [0, π].
    static func angleDifference(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        var d = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
        if d < 0 { d += 2 * .pi }
        return d > .pi ? 2 * .pi - d : d
    }

    /// Normalizes an angle to (-π, π].
    static func normalizeAngle(_ a: CGFloat) -> CGFloat {
        var r = a.truncatingRemainder(dividingBy: 2 * .pi)
        if r <= -.pi { r += 2 * .pi }
        if r > .pi { r -= 2 * .pi }
        return r
    }

    /// Ramer–Douglas–Peucker simplification.
    static func simplify(_ pts: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true
        keep[pts.count - 1] = true
        var stack: [(Int, Int)] = [(0, pts.count - 1)]
        while let (s, e) = stack.popLast() {
            guard e > s + 1 else { continue }
            var maxD: CGFloat = 0
            var idx = s
            for i in (s + 1)..<e {
                let d = distance(from: pts[i], toSegment: pts[s], pts[e])
                if d > maxD { maxD = d; idx = i }
            }
            if maxD > epsilon {
                keep[idx] = true
                stack.append((s, idx))
                stack.append((idx, e))
            }
        }
        return pts.enumerated().compactMap { keep[$0.offset] ? $0.element : nil }
    }

    static func polylineIntersectsRect(_ pts: [CGPoint], _ rect: CGRect) -> Bool {
        if pts.contains(where: { rect.contains($0) }) { return true }
        let c = rect.corners
        for i in 1..<max(pts.count, 1) {
            for k in 0..<4 where segmentsIntersect(pts[i - 1], pts[i], c[k], c[(k + 1) % 4]) {
                return true
            }
        }
        return false
    }
}
