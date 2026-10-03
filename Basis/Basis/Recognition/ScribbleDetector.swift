import CoreGraphics
import Foundation

/// Recognizes the rapid back-and-forth "scribble out" gesture.
///
/// A scribble is characterised by many large reversals relative to its own
/// extent, a high ink density (path length ≫ size) and speed. The pen tool
/// additionally requires the scribble to cover existing content before it
/// erases anything, which keeps normal handwriting (e.g. "mmm", "lll") safe.
struct ScribbleDetector {
    struct Metrics {
        var majorReversals: Int
        var minorReversals: Int
        var density: CGFloat
        var speed: CGFloat          // screen points / second
        var majorExtent: CGFloat    // screen points
        var minorExtent: CGFloat
        var duration: TimeInterval
    }

    var minMajorReversals = 4
    var minMinorReversals = 8
    var minDensity: CGFloat = 3.2
    /// Dense zig-zags are only accepted when much denser than cursive ("mmm", "lll" ≈ 5–6.5).
    var minZigZagDensity: CGFloat = 7
    var minSpeed: CGFloat = 250
    var maxDuration: TimeInterval = 4

    /// - Parameters:
    ///   - points: page-space samples
    ///   - times: timestamps for each sample (seconds)
    ///   - zoom: page → screen scale, so thresholds are in physical units
    func analyze(points: [CGPoint], times: [TimeInterval], zoom: CGFloat) -> Metrics? {
        guard points.count >= 12, points.count == times.count, let t0 = times.first, let t1 = times.last else { return nil }
        let screen = points.map { $0 * zoom }
        let length = Geometry.pathLength(screen)
        let box = CGRect.bounding(screen)
        guard box.diagonal >= 10, length > 0 else { return nil }
        let spaced = Geometry.resample(screen, spacing: max(1.5, box.diagonal / 80))
        guard spaced.count >= 8 else { return nil }

        let axes = Geometry.principalAxes(spaced)
        let major = spaced.map { ($0 - axes.centroid).dot(axes.major) }
        let minor = spaced.map { ($0 - axes.centroid).dot(axes.minor) }
        let majorExtent = (major.max() ?? 0) - (major.min() ?? 0)
        let minorExtent = (minor.max() ?? 0) - (minor.min() ?? 0)

        let duration = max(t1 - t0, 0.001)
        return Metrics(
            majorReversals: Self.reversals(major, hysteresis: max(4, majorExtent * 0.4)),
            minorReversals: Self.reversals(minor, hysteresis: max(4, minorExtent * 0.5)),
            density: length / max(box.diagonal, 1),
            speed: length / CGFloat(duration),
            majorExtent: majorExtent,
            minorExtent: minorExtent,
            duration: duration)
    }

    func isScribble(_ m: Metrics) -> Bool {
        guard m.duration <= maxDuration, m.speed >= minSpeed else { return false }
        // Back-and-forth along the long axis (the classic scribble over a word).
        if m.majorReversals >= minMajorReversals && m.density >= minDensity { return true }
        // Very tight, fast zig-zag across the short axis while sweeping along
        // the long one. Kept strict: cursive handwriting has the same shape
        // but is far less dense.
        if m.minorReversals >= minMinorReversals && m.density >= minZigZagDensity
            && m.speed >= minSpeed * 1.6 && m.minorExtent >= m.majorExtent * 0.15 {
            return true
        }
        return false
    }

    func isScribble(points: [CGPoint], times: [TimeInterval], zoom: CGFloat) -> Bool {
        guard let m = analyze(points: points, times: times, zoom: zoom) else { return false }
        return isScribble(m)
    }

    /// Counts direction reversals of a 1-D signal, ignoring wiggles smaller
    /// than `hysteresis`.
    static func reversals(_ values: [CGFloat], hysteresis h: CGFloat) -> Int {
        guard var extreme = values.first else { return 0 }
        var direction = 0
        var count = 0
        for v in values.dropFirst() {
            switch direction {
            case 0:
                if v - extreme > h { direction = 1; extreme = v } else if extreme - v > h { direction = -1; extreme = v }
            case 1:
                if v > extreme { extreme = v } else if extreme - v > h { count += 1; direction = -1; extreme = v }
            default:
                if v < extreme { extreme = v } else if v - extreme > h { count += 1; direction = 1; extreme = v }
            }
        }
        return count
    }
}
