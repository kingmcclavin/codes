import CoreGraphics
import Foundation

/// Vector erasing: splits strokes where they are touched instead of painting
/// over them, so erased ink stays fully editable.
enum ErasureEngine {
    /// Erases the parts of `stroke` within `radius` of the polyline `path`.
    /// Returns nil when the stroke is untouched, otherwise the surviving
    /// fragments (possibly empty).
    static func erase(_ stroke: Stroke, along path: [CGPoint], radius: CGFloat) -> [Stroke]? {
        guard !path.isEmpty else { return nil }
        let pathBounds = CGRect.bounding(path).expanded(by: radius + stroke.style.maximumWidth)
        guard stroke.bounds.intersects(pathBounds) else { return nil }
        let reach = radius + stroke.style.width * 0.5
        return split(stroke, spacing: max(0.5, radius * 0.4)) { p in
            pathBounds.contains(p) && Geometry.distance(from: p, toPolyline: path) <= reach
        }
    }

    /// Erases the parts of `stroke` inside `polygon`.
    static func erase(_ stroke: Stroke, inside polygon: [CGPoint]) -> [Stroke]? {
        let box = CGRect.bounding(polygon)
        guard stroke.bounds.intersects(box) else { return nil }
        return split(stroke, spacing: max(0.5, box.diagonal / 200)) { p in
            box.contains(p) && Geometry.polygonContains(polygon, p)
        }
    }

    /// Densifies the stroke, removes samples matching `isErased`, and returns
    /// the remaining runs as new strokes.
    static func split(_ stroke: Stroke, spacing: CGFloat, isErased: (CGPoint) -> Bool) -> [Stroke]? {
        let dense = densify(stroke.points, spacing: spacing)
        var erasedAny = false
        var runs: [[InkPoint]] = []
        var current: [InkPoint] = []
        for p in dense {
            if isErased(p.location) {
                erasedAny = true
                if !current.isEmpty { runs.append(current); current = [] }
            } else {
                current.append(p)
            }
        }
        if !current.isEmpty { runs.append(current) }
        guard erasedAny else { return nil }

        let minLength = max(0.5, stroke.style.width * 0.3)
        return runs.compactMap { run in
            guard run.count > 1 || stroke.points.count == 1 else { return nil }
            if run.count > 1 && Geometry.pathLength(run.map(\.location)) < minLength { return nil }
            return Stroke(points: simplifyDense(run), style: stroke.style, createdAt: stroke.createdAt)
        }
    }

    /// Inserts interpolated samples so no gap exceeds `spacing`.
    static func densify(_ pts: [InkPoint], spacing: CGFloat) -> [InkPoint] {
        guard pts.count > 1 else { return pts }
        var out: [InkPoint] = [pts[0]]
        out.reserveCapacity(pts.count)
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            let d = a.location.distance(to: b.location)
            let n = Int(d / spacing)
            if n > 0 {
                for k in 1...n {
                    out.append(a.interpolated(to: b, t: Float(CGFloat(k) / CGFloat(n + 1))))
                }
            }
            out.append(b)
        }
        return out
    }

    /// Removes the extra interpolated samples on straight runs to keep
    /// fragments compact (keeps curvature and pressure changes).
    private static func simplifyDense(_ pts: [InkPoint]) -> [InkPoint] {
        guard pts.count > 8 else { return pts }
        var out: [InkPoint] = [pts[0]]
        for i in 1..<(pts.count - 1) {
            let prev = out[out.count - 1], cur = pts[i], next = pts[i + 1]
            let dev = Geometry.distance(from: cur.location, toSegment: prev.location, next.location)
            let pressureJump = abs(cur.force - prev.force) > 0.03
            if dev > 0.08 || pressureJump || prev.location.distance(to: cur.location) > 6 {
                out.append(cur)
            }
        }
        out.append(pts[pts.count - 1])
        return out
    }
}
