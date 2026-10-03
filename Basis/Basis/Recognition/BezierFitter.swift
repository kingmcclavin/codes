import CoreGraphics
import Foundation

/// Least-squares cubic Bézier fitting (Philip J. Schneider, "An Algorithm for
/// Automatically Fitting Digitized Curves", Graphics Gems 1990).
enum BezierFitter {
    /// Returns a Bézier chain p0, c1, c2, p1, c1, c2, p2, … fitting `points`
    /// within `tolerance`.
    static func fit(_ input: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        var pts: [CGPoint] = []
        for p in input where pts.last.map({ $0.distance(to: p) > 1e-3 }) ?? true { pts.append(p) }
        guard pts.count >= 2 else { return pts }
        if pts.count == 2 {
            let d = pts[0].distance(to: pts[1]) / 3
            let t = (pts[1] - pts[0]).normalized
            return [pts[0], pts[0] + t * d, pts[1] - t * d, pts[1]]
        }
        var out: [CGPoint] = [pts[0]]
        let tHat1 = leftTangent(pts, 0)
        let tHat2 = rightTangent(pts, pts.count - 1)
        fitCubic(pts, first: 0, last: pts.count - 1, tHat1: tHat1, tHat2: tHat2, error: tolerance * tolerance, out: &out, depth: 0)
        return out
    }

    private static func leftTangent(_ p: [CGPoint], _ i: Int) -> CGPoint {
        let j = min(i + 2, p.count - 1)
        return (p[j] - p[i]).normalized
    }

    private static func rightTangent(_ p: [CGPoint], _ i: Int) -> CGPoint {
        let j = max(i - 2, 0)
        return (p[j] - p[i]).normalized
    }

    private static func centerTangent(_ p: [CGPoint], _ i: Int) -> CGPoint {
        let a = p[max(i - 1, 0)], b = p[min(i + 1, p.count - 1)]
        let v = (a - b).normalized
        return v == .zero ? (p[max(i - 1, 0)] - p[i]).normalized : v
    }

    private static func fitCubic(_ p: [CGPoint], first: Int, last: Int, tHat1: CGPoint, tHat2: CGPoint,
                                 error: CGFloat, out: inout [CGPoint], depth: Int) {
        let n = last - first + 1
        if n == 2 || depth > 12 {
            let d = p[first].distance(to: p[last]) / 3
            out.append(p[first] + tHat1 * d)
            out.append(p[last] + tHat2 * d)
            out.append(p[last])
            return
        }

        var u = chordLengthParameterize(p, first, last)
        var bez = generateBezier(p, first, last, u, tHat1, tHat2)
        var (maxError, split) = computeMaxError(p, first, last, bez, u)
        if maxError < error {
            out.append(contentsOf: bez[1...3])
            return
        }

        if maxError < error * 4 {
            for _ in 0..<4 {
                u = reparameterize(p, first, last, u, bez)
                bez = generateBezier(p, first, last, u, tHat1, tHat2)
                (maxError, split) = computeMaxError(p, first, last, bez, u)
                if maxError < error {
                    out.append(contentsOf: bez[1...3])
                    return
                }
            }
        }

        split = split.clamped(first + 1, last - 1)
        let tc = centerTangent(p, split)
        fitCubic(p, first: first, last: split, tHat1: tHat1, tHat2: tc, error: error, out: &out, depth: depth + 1)
        fitCubic(p, first: split, last: last, tHat1: -tc, tHat2: tHat2, error: error, out: &out, depth: depth + 1)
    }

    private static func chordLengthParameterize(_ p: [CGPoint], _ first: Int, _ last: Int) -> [CGFloat] {
        var u: [CGFloat] = [0]
        for i in (first + 1)...last {
            u.append(u[u.count - 1] + p[i].distance(to: p[i - 1]))
        }
        let total = u[u.count - 1]
        guard total > 0 else { return u.indices.map { CGFloat($0) / CGFloat(max(u.count - 1, 1)) } }
        return u.map { $0 / total }
    }

    private static func bezierPoint(_ b: [CGPoint], _ t: CGFloat) -> CGPoint {
        let mt = 1 - t
        return b[0] * (mt * mt * mt) + b[1] * (3 * mt * mt * t) + b[2] * (3 * mt * t * t) + b[3] * (t * t * t)
    }

    private static func generateBezier(_ p: [CGPoint], _ first: Int, _ last: Int, _ u: [CGFloat],
                                       _ tHat1: CGPoint, _ tHat2: CGPoint) -> [CGPoint] {
        let p0 = p[first], p3 = p[last]
        var c00: CGFloat = 0, c01: CGFloat = 0, c11: CGFloat = 0, x0: CGFloat = 0, x1: CGFloat = 0
        for (k, i) in (first...last).enumerated() {
            let t = u[k], mt = 1 - t
            let b0 = mt * mt * mt, b1 = 3 * t * mt * mt, b2 = 3 * t * t * mt, b3 = t * t * t
            let a1 = tHat1 * b1, a2 = tHat2 * b2
            c00 += a1.dot(a1); c01 += a1.dot(a2); c11 += a2.dot(a2)
            let tmp = p[i] - (p0 * (b0 + b1) + p3 * (b2 + b3))
            x0 += a1.dot(tmp); x1 += a2.dot(tmp)
        }
        let det = c00 * c11 - c01 * c01
        var alphaL: CGFloat = 0, alphaR: CGFloat = 0
        if abs(det) > 1e-12 {
            alphaL = (x0 * c11 - x1 * c01) / det
            alphaR = (c00 * x1 - c01 * x0) / det
        }
        let segLength = p0.distance(to: p3)
        let epsilon = 1e-6 * segLength
        if alphaL < epsilon || alphaR < epsilon {
            let d = segLength / 3
            return [p0, p0 + tHat1 * d, p3 + tHat2 * d, p3]
        }
        return [p0, p0 + tHat1 * alphaL, p3 + tHat2 * alphaR, p3]
    }

    private static func computeMaxError(_ p: [CGPoint], _ first: Int, _ last: Int, _ b: [CGPoint],
                                        _ u: [CGFloat]) -> (CGFloat, Int) {
        var maxD: CGFloat = 0
        var split = (last - first + 1) / 2 + first
        for (k, i) in (first...last).enumerated() {
            let d = bezierPoint(b, u[k]).distanceSquared(to: p[i])
            if d >= maxD { maxD = d; split = i }
        }
        return (maxD, split)
    }

    private static func reparameterize(_ p: [CGPoint], _ first: Int, _ last: Int, _ u: [CGFloat], _ b: [CGPoint]) -> [CGFloat] {
        (first...last).enumerated().map { k, i in newtonRaphson(b, p[i], u[k]) }
    }

    private static func newtonRaphson(_ q: [CGPoint], _ p: CGPoint, _ u: CGFloat) -> CGFloat {
        let q1 = [(q[1] - q[0]) * 3, (q[2] - q[1]) * 3, (q[3] - q[2]) * 3]
        let q2 = [(q1[1] - q1[0]) * 2, (q1[2] - q1[1]) * 2]
        let mt = 1 - u
        let qu = bezierPoint(q, u)
        let q1u = q1[0] * (mt * mt) + q1[1] * (2 * mt * u) + q1[2] * (u * u)
        let q2u = q2[0] * mt + q2[1] * u
        let num = (qu - p).dot(q1u)
        let den = q1u.dot(q1u) + (qu - p).dot(q2u)
        guard abs(den) > 1e-12 else { return u }
        return (u - num / den).clamped(0, 1)
    }
}
