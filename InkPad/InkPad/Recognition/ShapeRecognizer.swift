import CoreGraphics
import Foundation

struct RecognitionContext {
    /// Existing key points (shape vertices, line endpoints, centers) that new
    /// shapes snap to.
    var snapPoints: [CGPoint] = []
    /// Snap distance in page points.
    var snapTolerance: CGFloat = 10
    /// Existing straight lines that a small "V" stroke can turn into arrows.
    var lines: [(id: UUID, start: CGPoint, end: CGPoint)] = []
}

enum RecognitionResult {
    case shape(ShapeGeometry, ArrowHeads)
    /// Add an arrow head to an existing line.
    case addArrowHead(lineID: UUID, atEnd: Bool)
}

/// Converts a rough freehand stroke into clean geometry.
///
/// The recognizer fits *intended* geometry rather than smoothing the input:
/// polygon sides are least-squares lines whose intersections become the
/// vertices, near-right angles become right angles, near-axis edges become
/// axis aligned, circles/squares are regularized, and endpoints snap to
/// existing shapes.
struct ShapeRecognizer {
    var sampleCount = 96
    /// Angles (radians) within which lines snap to horizontal/vertical.
    var axisSnap: CGFloat = 5 * .pi / 180
    var diagonalSnap: CGFloat = 3 * .pi / 180
    /// Maximum Bézier segments for a stroke to be recognized as a curve.
    var maxCurveSegments = 4

    func recognize(_ input: [CGPoint], context: RecognitionContext = RecognitionContext()) -> RecognitionResult? {
        var pts: [CGPoint] = []
        for p in input where pts.last.map({ $0.distance(to: p) > 0.25 }) ?? true { pts.append(p) }
        guard pts.count >= 2 else { return nil }
        let diag = max(CGRect.bounding(pts).diagonal, 1)
        guard Geometry.pathLength(pts) >= 8 else { return nil }
        // Light smoothing removes sensor/hand jitter before measuring
        // straightness and curvature; `raw` keeps sharp features (arrow tips).
        let raw = Geometry.resample(pts, count: sampleCount)
        let rs = smoothOpen(raw, passes: 2)
        let length = Geometry.pathLength(rs)

        if let line = detectLine(rs, length: length) {
            return .shape(snapLine(line.0, line.1, context: context), .none)
        }
        if let closed = closedLoop(rs, diag: diag, length: length) {
            let loop = resampleLoop(closed, count: sampleCount)
            if let poly = detectPolygon(loop, diag: diag, context: context) { return .shape(poly, .none) }
            if let ell = detectEllipse(loop, context: context) { return .shape(ell, .none) }
            return nil
        }
        if let arrow = detectArrow(rs, raw: raw, context: context) { return arrow }
        if let upgrade = detectArrowHeadForLine(rs, diag: diag, context: context) { return upgrade }
        if let polyline = detectPolyline(rs, context: context) { return .shape(polyline, .none) }
        // Only simple curves count as an intended shape; anything more complex
        // (e.g. a word the user paused on) stays as handwriting.
        let curve = fitCurve(pts, diag: diag)
        if case let .curve(cp) = curve, (cp.count - 1) / 3 <= maxCurveSegments { return .shape(curve, .none) }
        return nil
    }

    /// Smooth curve fallback (used by the Shapes tool when nothing else matches).
    func fitCurve(_ pts: [CGPoint], diag: CGFloat) -> ShapeGeometry {
        let spaced = Geometry.resample(pts, spacing: max(1.5, diag / 120))
        let smoothed = smoothOpen(spaced, passes: 2)
        return .curve(points: BezierFitter.fit(smoothed, tolerance: max(1.2, diag * 0.012)))
    }

    // MARK: - Lines

    private func detectLine(_ rs: [CGPoint], length: CGFloat) -> (CGPoint, CGPoint)? {
        guard let a = rs.first, let b = rs.last else { return nil }
        let chord = a.distance(to: b)
        guard chord > 4, chord / length > 0.93 else { return nil }
        let fit = Geometry.fitLine(rs)
        var maxDev: CGFloat = 0
        for p in rs {
            maxDev = max(maxDev, abs((p - fit.point).cross(fit.direction)))
        }
        guard maxDev < max(2.5, chord * 0.07) else { return nil }
        // Endpoints: project the actual ends onto the fitted line.
        func project(_ p: CGPoint) -> CGPoint { fit.point + fit.direction * (p - fit.point).dot(fit.direction) }
        return (project(a), project(b))
    }

    private func nearestSnap(_ p: CGPoint, _ context: RecognitionContext) -> CGPoint? {
        var best: CGPoint?
        var bestD = context.snapTolerance
        for q in context.snapPoints {
            let d = q.distance(to: p)
            if d <= bestD { bestD = d; best = q }
        }
        return best
    }

    /// Snaps an angle to 0/90/180/270 (and 45° multiples more tightly).
    private func snapAngle(_ angle: CGFloat) -> CGFloat {
        for k in 0..<8 {
            let target = CGFloat(k) * .pi / 4
            let tol = k % 2 == 0 ? axisSnap : diagonalSnap
            if Geometry.angleDifference(angle, target) < tol { return target }
        }
        return angle
    }

    private func snapLine(_ s0: CGPoint, _ e0: CGPoint, context: RecognitionContext) -> ShapeGeometry {
        let sSnap = nearestSnap(s0, context)
        let eSnap = nearestSnap(e0, context)
        if let sSnap, let eSnap, sSnap.distance(to: eSnap) > 1 { return .line(start: sSnap, end: eSnap) }
        if let eSnap, sSnap == nil {
            // Anchor at the snapped end and straighten the free end.
            let len = e0.distance(to: s0)
            let ang = snapAngle((s0 - eSnap).angle)
            return .line(start: eSnap + CGPoint.unit(angle: ang) * len, end: eSnap)
        }
        let anchor = sSnap ?? s0
        let len = anchor.distance(to: e0)
        let ang = snapAngle((e0 - anchor).angle)
        return .line(start: anchor, end: anchor + CGPoint.unit(angle: ang) * len)
    }

    // MARK: - Closed shapes

    private func closedLoop(_ rs: [CGPoint], diag: CGFloat, length: CGFloat) -> [CGPoint]? {
        guard let first = rs.first, let last = rs.last, length > diag * 1.6 else { return nil }
        if first.distance(to: last) <= diag * 0.22 { return rs }
        // Overshoot: the stroke passes the start and keeps going. Trim at the
        // point in the last part of the stroke that comes closest to the start.
        let startIdx = Int(Double(rs.count) * 0.55)
        var bestI = -1
        var bestD = CGFloat.greatestFiniteMagnitude
        for i in startIdx..<rs.count {
            let d = rs[i].distance(to: first)
            if d < bestD { bestD = d; bestI = i }
        }
        if bestI > 0, bestD <= diag * 0.12 { return Array(rs[0...bestI]) }
        return nil
    }

    private func resampleLoop(_ pts: [CGPoint], count: Int) -> [CGPoint] {
        guard let first = pts.first else { return pts }
        let closed = pts + [first]
        var r = Geometry.resample(closed, count: count + 1)
        if r.count > count { r.removeLast() }
        return r
    }

    /// Windowed turning angle at each sample (radians).
    private func turning(_ p: [CGPoint], window k: Int, closed: Bool) -> [CGFloat] {
        let n = p.count
        return (0..<n).map { i -> CGFloat in
            let a: CGPoint, b: CGPoint
            if closed {
                a = p[(i - k + n) % n]; b = p[(i + k) % n]
            } else {
                guard i - k >= 0, i + k < n else { return 0 }
                a = p[i - k]; b = p[i + k]
            }
            let v1 = p[i] - a, v2 = b - p[i]
            guard v1.length > 1e-6, v2.length > 1e-6 else { return 0 }
            return Geometry.angleDifference(v1.angle, v2.angle)
        }
    }

    /// Indices of corners (local maxima of turning above `threshold`).
    private func corners(_ p: [CGPoint], window k: Int, threshold: CGFloat, closed: Bool) -> [Int] {
        let turn = turning(p, window: k, closed: closed)
        let n = p.count
        let candidates = (0..<n).filter { turn[$0] > threshold }.sorted { turn[$0] > turn[$1] }
        var accepted: [Int] = []
        for c in candidates {
            let tooClose = accepted.contains { a in
                let d = abs(a - c)
                return (closed ? min(d, n - d) : d) <= k + 1
            }
            if !tooClose { accepted.append(c) }
        }
        return accepted.sorted()
    }

    private func detectPolygon(_ loop: [CGPoint], diag: CGFloat, context: RecognitionContext) -> ShapeGeometry? {
        let n = loop.count
        let cs = corners(loop, window: 4, threshold: 40 * .pi / 180, closed: true)
        guard cs.count >= 3, cs.count <= 8 else { return nil }

        // Fit a line to the interior of every side.
        var lines: [(point: CGPoint, direction: CGPoint)] = []
        for j in 0..<cs.count {
            let a = cs[j], b = cs[(j + 1) % cs.count]
            let span = (b - a + n) % n
            guard span >= 3 else { return nil }
            let trim = max(1, span / 6)
            let side = ((a + trim)...(a + span - trim)).map { loop[$0 % n] }
            let fit = Geometry.fitLine(side)
            let sideLen = loop[a].distance(to: loop[b % n])
            let maxDev = side.map { abs(($0 - fit.point).cross(fit.direction)) }.max() ?? 0
            guard maxDev <= max(2.5, sideLen * 0.12) else { return nil }   // side is curved
            lines.append(fit)
        }

        var vertices: [CGPoint] = []
        for j in 0..<cs.count {
            let l1 = lines[(j - 1 + cs.count) % cs.count], l2 = lines[j]
            let sample = loop[cs[j]]
            if let x = Geometry.lineIntersection(l1.point, l1.direction, l2.point, l2.direction),
               x.distance(to: sample) < diag * 0.25 {
                vertices.append(x)
            } else {
                vertices.append(sample)
            }
        }

        // Reject if the polygon doesn't describe the stroke well.
        let closedVerts = vertices + [vertices[0]]
        let meanErr = loop.reduce(0) { $0 + Geometry.distance(from: $1, toPolyline: closedVerts) } / CGFloat(n)
        guard meanErr / diag < 0.035 else { return nil }
        // Degenerate (tiny) sides indicate a mis-detected corner.
        let perimeter = Geometry.pathLength(closedVerts)
        for j in 0..<vertices.count where vertices[j].distance(to: vertices[(j + 1) % vertices.count]) < perimeter * 0.04 {
            return nil
        }

        switch vertices.count {
        case 3:
            return .polygon(points: regularizeTriangle(vertices, context: context), closed: true)
        case 4:
            if let rect = rectangle(from: vertices, context: context) { return rect }
            return .polygon(points: snapPolygonRotation(vertices), closed: true)
        default:
            return .polygon(points: regularizePolygon(vertices), closed: true)
        }
    }

    private func interiorAngles(_ v: [CGPoint]) -> [CGFloat] {
        let n = v.count
        return (0..<n).map { i -> CGFloat in
            let a = v[(i - 1 + n) % n] - v[i], b = v[(i + 1) % n] - v[i]
            return Geometry.angleDifference(a.angle, b.angle)
        }
    }

    private func rectangle(from v: [CGPoint], context: RecognitionContext) -> ShapeGeometry? {
        let tol: CGFloat = 13 * .pi / 180
        guard interiorAngles(v).allSatisfy({ abs($0 - .pi / 2) < tol }) else { return nil }
        // Dominant orientation: circular mean of edge angles modulo 90°.
        var sx: CGFloat = 0, sy: CGFloat = 0
        for i in 0..<4 {
            let e = v[(i + 1) % 4] - v[i]
            let a = 4 * e.angle
            sx += cos(a) * e.length; sy += sin(a) * e.length
        }
        var theta = atan2(sy, sx) / 4
        if Geometry.angleDifference(theta, 0) < 7 * .pi / 180 { theta = 0 }
        let u = CGPoint.unit(angle: theta), w = u.perpendicular
        let pu = v.map { $0.dot(u) }, pw = v.map { $0.dot(w) }
        // Average opposite sides rather than taking extremes (less sensitive to overshoot).
        let su = pu.sorted(), sw = pw.sorted()
        var width = ((su[2] + su[3]) - (su[0] + su[1])) / 2
        var height = ((sw[2] + sw[3]) - (sw[0] + sw[1])) / 2
        var center = u * ((su[0] + su[3]) / 2) + w * ((sw[0] + sw[3]) / 2)
        if abs(width - height) / max(width, height) < 0.1 {
            let s = (width + height) / 2
            width = s; height = s
        }
        if let snap = nearestSnap(center, context) { center = snap }
        return .rectangle(BoxGeometry(center: center, size: CGSize(width: width, height: height), rotation: theta))
    }

    private func centroid(_ v: [CGPoint]) -> CGPoint {
        v.reduce(CGPoint.zero, +) / CGFloat(max(v.count, 1))
    }

    /// Rotates a polygon about its centroid so its most axis-aligned edge
    /// becomes exactly horizontal/vertical, if it is already close.
    private func snapPolygonRotation(_ v: [CGPoint]) -> [CGPoint] {
        var best: CGFloat = .greatestFiniteMagnitude
        var correction: CGFloat = 0
        for i in 0..<v.count {
            let a = (v[(i + 1) % v.count] - v[i]).angle
            for k in 0..<4 {
                let target = CGFloat(k) * .pi / 2
                let d = Geometry.normalizeAngle(target - a)
                if abs(d) < best { best = abs(d); correction = d }
            }
        }
        guard best < axisSnap, best > 1e-6 else { return v }
        let c = centroid(v)
        return v.map { $0.rotated(by: correction, around: c) }
    }

    private func regularizeTriangle(_ input: [CGPoint], context: RecognitionContext) -> [CGPoint] {
        var v = input
        let angles = interiorAngles(v)
        let tol: CGFloat = 7 * .pi / 180
        if angles.allSatisfy({ abs($0 - .pi / 3) < tol }) {
            // Equilateral: keep centroid, average size, orientation of first edge.
            let c = centroid(v)
            let r = v.reduce(0) { $0 + $1.distance(to: c) } / 3
            let start = (v[0] - c).angle
            v = (0..<3).map { c + CGPoint.unit(angle: start + CGFloat($0) * 2 * .pi / 3) * r }
            // Keep original winding order.
            if Geometry.polygonArea(v) * Geometry.polygonArea(input) < 0 { v = [v[0], v[2], v[1]] }
        } else if let right = angles.firstIndex(where: { abs($0 - .pi / 2) < tol }) {
            // Right triangle: move the right-angle vertex onto the Thales circle.
            let a = v[(right + 2) % 3], b = v[(right + 1) % 3]
            let mid = a.midpoint(b), r = a.distance(to: b) / 2
            let dir = (v[right] - mid).normalized
            if dir != .zero { v[right] = mid + dir * r }
        }
        v = snapPolygonRotation(v)
        return v.map { nearestSnap($0, context) ?? $0 }
    }

    private func regularizePolygon(_ v: [CGPoint]) -> [CGPoint] {
        let n = v.count
        let sides = (0..<n).map { v[$0].distance(to: v[($0 + 1) % n]) }
        let mean = sides.reduce(0, +) / CGFloat(n)
        let dev = sides.map { abs($0 - mean) }.max() ?? 0
        let regularAngle = CGFloat(n - 2) * .pi / CGFloat(n)
        let anglesOK = interiorAngles(v).allSatisfy { abs($0 - regularAngle) < 12 * .pi / 180 }
        guard dev / mean < 0.2, anglesOK else { return snapPolygonRotation(v) }
        let c = centroid(v)
        let r = v.reduce(0) { $0 + $1.distance(to: c) } / CGFloat(n)
        let start = (v[0] - c).angle
        let sign: CGFloat = Geometry.polygonArea(v) >= 0 ? 1 : -1
        let regular = (0..<n).map { c + CGPoint.unit(angle: start + sign * CGFloat($0) * 2 * .pi / CGFloat(n)) * r }
        return snapPolygonRotation(regular)
    }

    private func detectEllipse(_ loop: [CGPoint], context: RecognitionContext) -> ShapeGeometry? {
        let axes = Geometry.principalAxes(loop)
        var theta = axes.major.angle
        let u = axes.major, w = axes.minor
        // Center from the extents in the principal frame (robust to uneven sampling).
        let pu = loop.map { ($0 - axes.centroid).dot(u) }, pw = loop.map { ($0 - axes.centroid).dot(w) }
        let cu = (pu.min()! + pu.max()!) / 2, cw = (pw.min()! + pw.max()!) / 2
        var center = axes.centroid + u * cu + w * cw
        let lu = pu.map { $0 - cu }, lw = pw.map { $0 - cw }

        // Least squares for A u² + B w² = 1.
        var s40: CGFloat = 0, s22: CGFloat = 0, s04: CGFloat = 0, s20: CGFloat = 0, s02: CGFloat = 0
        for i in 0..<loop.count {
            let u2 = lu[i] * lu[i], w2 = lw[i] * lw[i]
            s40 += u2 * u2; s22 += u2 * w2; s04 += w2 * w2; s20 += u2; s02 += w2
        }
        let det = s40 * s04 - s22 * s22
        guard abs(det) > 1e-9 else { return nil }
        let A = (s20 * s04 - s02 * s22) / det
        let B = (s40 * s02 - s22 * s20) / det
        guard A > 0, B > 0 else { return nil }
        var a = 1 / A.squareRoot(), b = 1 / B.squareRoot()

        var err: CGFloat = 0
        for i in 0..<loop.count {
            err += abs((lu[i] * lu[i] * A + lw[i] * lw[i] * B).squareRoot() - 1)
        }
        err /= CGFloat(loop.count)
        guard err < 0.12, min(a, b) > 1 else { return nil }

        if min(a, b) / max(a, b) > 0.86 {
            let r = (a + b) / 2
            a = r; b = r; theta = 0
        } else {
            // Snap near-axis ellipses.
            if Geometry.angleDifference(theta, 0) < 8 * .pi / 180 || Geometry.angleDifference(theta, .pi) < 8 * .pi / 180 {
                theta = 0
            } else if Geometry.angleDifference(theta, .pi / 2) < 8 * .pi / 180 || Geometry.angleDifference(theta, -.pi / 2) < 8 * .pi / 180 {
                theta = 0; swap(&a, &b)
            }
        }
        if let snap = nearestSnap(center, context) { center = snap }
        return .ellipse(BoxGeometry(center: center, size: CGSize(width: 2 * a, height: 2 * b), rotation: theta))
    }

    // MARK: - Open shapes

    private func straightness(_ pts: ArraySlice<CGPoint>) -> CGFloat {
        guard let a = pts.first, let b = pts.last else { return 0 }
        let len = Geometry.pathLength(Array(pts))
        return len > 0 ? a.distance(to: b) / len : 0
    }

    /// Single-stroke arrow: a straight shaft followed by a head that doubles back near the tip.
    private func detectArrow(_ rs: [CGPoint], raw: [CGPoint], context: RecognitionContext) -> RecognitionResult? {
        if let r = arrowForward(rs, raw: raw, context: context) { return r }
        // The head may also have been drawn first.
        if let r = arrowForward(Array(rs.reversed()), raw: Array(raw.reversed()), context: context) { return r }
        return nil
    }

    private func arrowForward(_ rs: [CGPoint], raw: [CGPoint], context: RecognitionContext) -> RecognitionResult? {
        let n = rs.count
        let turn = turning(rs, window: 2, closed: false)
        let from = Int(Double(n) * 0.35), to = Int(Double(n) * 0.95)
        guard from < to, let tip = (from..<to).first(where: { turn[$0] > 100 * .pi / 180 }) else { return nil }
        let shaft = rs[0...tip]
        guard straightness(shaft) > 0.93 else { return nil }
        let shaftFit = Geometry.fitLine(Array(shaft))
        var dir = shaftFit.direction
        if (rs[tip] - rs[0]).dot(dir) < 0 { dir = -dir }
        func project(_ p: CGPoint) -> CGPoint { shaftFit.point + shaftFit.direction * (p - shaftFit.point).dot(shaftFit.direction) }
        let start = project(raw[0]), tipPoint = project(raw[min(tip, raw.count - 1)])
        let shaftLen = start.distance(to: tipPoint)
        guard shaftLen > 12 else { return nil }

        let head = Array(rs[tip...])
        let headLen = Geometry.pathLength(head)
        guard headLen > shaftLen * 0.08, headLen < shaftLen * 1.6 else { return nil }
        guard head.allSatisfy({ $0.distance(to: tipPoint) < max(shaftLen * 0.45, 10) }) else { return nil }
        // Head strokes must point backwards along the shaft.
        let back = head.dropFirst().map { ($0 - tipPoint).normalized.dot(-dir) }
        guard !back.isEmpty, back.reduce(0, +) / CGFloat(back.count) > 0.45 else { return nil }

        guard case let .line(s, e) = snapLine(start, tipPoint, context: context) else { return nil }
        return .shape(.line(start: s, end: e), ArrowHeads(start: false, end: true))
    }

    /// A small "V" drawn at the end of an existing line becomes that line's arrow head.
    private func detectArrowHeadForLine(_ rs: [CGPoint], diag: CGFloat, context: RecognitionContext) -> RecognitionResult? {
        guard !context.lines.isEmpty else { return nil }
        let cs = corners(rs, window: 4, threshold: 50 * .pi / 180, closed: false)
        guard cs.count == 1 else { return nil }
        let apex = rs[cs[0]]
        let arms = [rs[0], rs[rs.count - 1]]
        for line in context.lines {
            let lineLen = line.start.distance(to: line.end)
            guard lineLen > 10, diag < max(80, lineLen * 0.6) else { continue }
            for atEnd in [true, false] {
                let endpoint = atEnd ? line.end : line.start
                let other = atEnd ? line.start : line.end
                guard apex.distance(to: endpoint) < max(14, diag * 0.35) else { continue }
                let outward = (endpoint - other).normalized
                let armsBack = arms.allSatisfy { ($0 - apex).normalized.dot(outward) < -0.25 }
                if armsBack { return .addArrowHead(lineID: line.id, atEnd: atEnd) }
            }
        }
        return nil
    }

    /// Open polyline made of straight segments (angles, axes, zig-zags).
    private func detectPolyline(_ rs: [CGPoint], context: RecognitionContext) -> ShapeGeometry? {
        let cs = corners(rs, window: 4, threshold: 40 * .pi / 180, closed: false)
        guard (1...5).contains(cs.count) else { return nil }
        let bounds = [0] + cs + [rs.count - 1]
        var lines: [(point: CGPoint, direction: CGPoint)] = []
        for j in 0..<(bounds.count - 1) {
            let a = bounds[j], b = bounds[j + 1]
            guard b - a >= 3 else { return nil }
            let trim = max(1, (b - a) / 6)
            let lo = j == 0 ? a : a + trim
            let hi = j == bounds.count - 2 ? b : b - trim
            guard hi > lo else { return nil }
            let seg = Array(rs[lo...hi])
            guard straightness(rs[a...b]) > 0.95 else { return nil }
            var fit = Geometry.fitLine(seg)
            // Axis-snap each segment direction (graph axes, right angles).
            let snapped = snapAngle(fit.direction.angle)
            fit.direction = CGPoint.unit(angle: snapped)
            lines.append(fit)
        }
        func project(_ p: CGPoint, _ l: (point: CGPoint, direction: CGPoint)) -> CGPoint {
            l.point + l.direction * (p - l.point).dot(l.direction)
        }
        var vertices = [nearestSnap(rs[0], context) ?? project(rs[0], lines[0])]
        for j in 1..<lines.count {
            let sample = rs[bounds[j]]
            if let x = Geometry.lineIntersection(lines[j - 1].point, lines[j - 1].direction, lines[j].point, lines[j].direction),
               x.distance(to: sample) < 40 {
                vertices.append(x)
            } else {
                vertices.append(sample)
            }
        }
        vertices.append(nearestSnap(rs[rs.count - 1], context) ?? project(rs[rs.count - 1], lines[lines.count - 1]))
        return .polygon(points: vertices, closed: false)
    }

    private func smoothOpen(_ p: [CGPoint], passes: Int) -> [CGPoint] {
        guard p.count > 2 else { return p }
        var s = p
        for _ in 0..<passes {
            var next = s
            for i in 1..<(s.count - 1) { next[i] = (s[i - 1] + s[i] * 2 + s[i + 1]) / 4 }
            s = next
        }
        return s
    }
}
