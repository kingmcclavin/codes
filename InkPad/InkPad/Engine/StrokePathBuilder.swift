import CoreGraphics
import Foundation

/// Converts stroke samples into a fillable vector outline.
///
/// Variable-width strokes are built as a smoothed left/right offset outline
/// with round caps. Constant-width and dashed strokes are built by stroking a
/// smoothed centerline. Either way the result is resolution independent.
enum StrokePathBuilder {
    struct Sample {
        var p: CGPoint
        var w: CGFloat
    }

    static func path(for stroke: Stroke) -> CGPath {
        path(points: stroke.points, style: stroke.style)
    }

    static func path(points: [InkPoint], style: StrokeStyle) -> CGPath {
        var samples = prepare(points: points, style: style)
        guard !samples.isEmpty else { return CGMutablePath() }

        if samples.count == 1 {
            let s = samples[0]
            let r = max(s.w / 2, 0.2)
            if style.isHighlighter {
                return CGPath(rect: CGRect(x: s.p.x - r * 0.35, y: s.p.y - r, width: r * 0.7, height: 2 * r), transform: nil)
            }
            return CGPath(ellipseIn: CGRect(x: s.p.x - r, y: s.p.y - r, width: 2 * r, height: 2 * r), transform: nil)
        }

        smooth(&samples)

        let widths = samples.map(\.w)
        let minW = widths.min() ?? 0, maxW = widths.max() ?? 0
        let isConstant = maxW - minW < max(0.04, maxW * 0.04)

        if style.lineStyle != .solid || style.isHighlighter || isConstant {
            let width = style.lineStyle == .solid && !style.isHighlighter
                ? (minW + maxW) / 2
                : style.width
            return strokedCenterline(samples.map(\.p), width: width, style: style)
        }
        return outline(samples)
    }

    // MARK: Preparation

    private static func prepare(points: [InkPoint], style: StrokeStyle) -> [Sample] {
        var result: [Sample] = []
        result.reserveCapacity(points.count)
        for pt in points {
            let s = Sample(p: pt.location, w: style.width(at: pt))
            if let last = result.last, last.p.distanceSquared(to: s.p) < 0.0025 {
                result[result.count - 1].w = max(last.w, s.w)
                continue
            }
            result.append(s)
        }
        return result
    }

    /// Light low-pass filter on positions and a stronger one on widths
    /// (pressure data is noisy). Endpoints are preserved.
    private static func smooth(_ s: inout [Sample]) {
        guard s.count > 2 else { return }
        for _ in 0..<2 {
            var next = s
            for i in 1..<(s.count - 1) {
                next[i].p = (s[i - 1].p + s[i].p * 2 + s[i + 1].p) / 4
            }
            s = next
        }
        for _ in 0..<3 {
            var next = s
            for i in 1..<(s.count - 1) {
                next[i].w = (s[i - 1].w + s[i].w * 2 + s[i + 1].w) / 4
            }
            s = next
        }
        // Taper the very ends slightly toward their neighbours so pressure
        // spikes at touch-down don't create blobs.
        s[0].w = min(s[0].w, s[1].w * 1.1)
        s[s.count - 1].w = min(s[s.count - 1].w, s[s.count - 2].w * 1.1)
    }

    // MARK: Centerline

    static func centerline(_ pts: [CGPoint]) -> CGMutablePath {
        let path = CGMutablePath()
        guard let first = pts.first else { return path }
        path.move(to: first)
        if pts.count == 2 {
            path.addLine(to: pts[1])
            return path
        }
        path.addLine(to: first.midpoint(pts[1]))
        for i in 1..<(pts.count - 1) {
            path.addQuadCurve(to: pts[i].midpoint(pts[i + 1]), control: pts[i])
        }
        path.addLine(to: pts[pts.count - 1])
        return path
    }

    private static func strokedCenterline(_ pts: [CGPoint], width: CGFloat, style: StrokeStyle) -> CGPath {
        var line: CGPath = centerline(pts)
        let cap: CGLineCap = style.isHighlighter ? .butt : .round
        if let dashes = style.lineStyle.dashPattern(width: width) {
            line = line.copy(dashingWithPhase: 0, lengths: dashes)
        }
        return line.copy(strokingWithWidth: max(width, 0.1), lineCap: style.lineStyle == .dotted ? .round : cap,
                         lineJoin: .round, miterLimit: 4)
    }

    // MARK: Variable-width outline

    private static func outline(_ samples: [Sample]) -> CGPath {
        let path = CGMutablePath()
        // Split at sharp corners so each run gets clean round caps; all runs
        // share orientation, so the non-zero fill rule unions them.
        var run: [Sample] = [samples[0]]
        for i in 1..<samples.count {
            run.append(samples[i])
            if i < samples.count - 1 {
                let a = (samples[i].p - samples[i - 1].p).normalized
                let b = (samples[i + 1].p - samples[i].p).normalized
                if a.dot(b) < -0.2 {
                    appendOutline(run, to: path)
                    run = [samples[i]]
                }
            }
        }
        appendOutline(run, to: path)
        return path
    }

    private static func appendOutline(_ s: [Sample], to path: CGMutablePath) {
        guard let first = s.first else { return }
        if s.count == 1 {
            let r = first.w / 2
            path.addEllipse(in: CGRect(x: first.p.x - r, y: first.p.y - r, width: 2 * r, height: 2 * r))
            return
        }
        let n = s.count
        var normals = [CGPoint](repeating: .zero, count: n)
        for i in 0..<n {
            let prev = s[max(i - 1, 0)].p
            let next = s[min(i + 1, n - 1)].p
            var t = (next - prev).normalized
            if t == .zero { t = CGPoint(x: 1, y: 0) }
            normals[i] = t.perpendicular
        }
        let left = (0..<n).map { s[$0].p + normals[$0] * (s[$0].w / 2) }
        let right = (0..<n).map { s[$0].p - normals[$0] * (s[$0].w / 2) }

        path.move(to: left[0])
        addSmooth(left, to: path)
        // End cap: from left side, around the tip, to the right side.
        path.addRelativeArc(center: s[n - 1].p, radius: s[n - 1].w / 2,
                            startAngle: normals[n - 1].angle, delta: -.pi)
        path.addLine(to: right[n - 1])
        addSmooth(right.reversed(), to: path)
        path.addRelativeArc(center: s[0].p, radius: s[0].w / 2,
                            startAngle: (-normals[0]).angle, delta: -.pi)
        path.closeSubpath()
    }

    /// Continues the current subpath through `pts` (whose first point is the
    /// current point) using midpoint quadratic smoothing.
    private static func addSmooth(_ pts: [CGPoint], to path: CGMutablePath) {
        guard pts.count > 1 else { return }
        if pts.count == 2 {
            path.addLine(to: pts[1])
            return
        }
        path.addLine(to: pts[0].midpoint(pts[1]))
        for i in 1..<(pts.count - 1) {
            path.addQuadCurve(to: pts[i].midpoint(pts[i + 1]), control: pts[i])
        }
        path.addLine(to: pts[pts.count - 1])
    }
}
