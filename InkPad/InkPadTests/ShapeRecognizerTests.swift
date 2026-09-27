import CoreGraphics
import XCTest
@testable import InkPad

final class ShapeRecognizerTests: XCTestCase {
    private var rng = SeededRandom(seed: 7)
    private let recognizer = ShapeRecognizer()

    // MARK: Helpers

    private func jitter(_ pts: [CGPoint], _ a: CGFloat = 1.2) -> [CGPoint] {
        pts.map { CGPoint(x: $0.x + rng.next(in: -a...a), y: $0.y + rng.next(in: -a...a)) }
    }

    /// Densely samples a polyline like a pencil would.
    private func trace(_ vertices: [CGPoint], closed: Bool = true, step: CGFloat = 2) -> [CGPoint] {
        let pts = closed ? vertices + [vertices[0]] : vertices
        var out: [CGPoint] = []
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            let n = max(1, Int(a.distance(to: b) / step))
            for k in 0..<n { out.append(a.lerp(to: b, t: CGFloat(k) / CGFloat(n))) }
        }
        out.append(pts[pts.count - 1])
        return out
    }

    private func ellipsePoints(center: CGPoint, rx: CGFloat, ry: CGFloat, rotation: CGFloat = 0, count: Int = 140, sweep: CGFloat = 1) -> [CGPoint] {
        (0...count).map { i in
            let t = CGFloat(i) / CGFloat(count) * 2 * .pi * sweep
            return CGPoint(x: rx * cos(t), y: ry * sin(t)).rotated(by: rotation) + center
        }
    }

    private func recognizeShape(_ pts: [CGPoint]) -> (ShapeGeometry, ArrowHeads)? {
        guard case let .shape(g, a)? = recognizer.recognize(pts) else { return nil }
        return (g, a)
    }

    // MARK: Tests

    func testStraightLineSnapsToHorizontal() throws {
        let (g, _) = try XCTUnwrap(recognizeShape(jitter(trace([.zero, CGPoint(x: 200, y: 5)], closed: false))))
        guard case let .line(s, e) = g else { return XCTFail("expected line, got \(g)") }
        XCTAssertEqual(s.y, e.y, accuracy: 0.001, "near-horizontal lines snap to horizontal")
        XCTAssertEqual(s.distance(to: e), 200, accuracy: 4)
    }

    func testDiagonalLine() throws {
        let (g, _) = try XCTUnwrap(recognizeShape(jitter(trace([.zero, CGPoint(x: 150, y: 140)], closed: false))))
        guard case .line = g else { return XCTFail("expected line, got \(g)") }
    }

    func testCircle() throws {
        let (g, _) = try XCTUnwrap(recognizeShape(jitter(ellipsePoints(center: CGPoint(x: 100, y: 100), rx: 80, ry: 80), 2)))
        guard case let .ellipse(b) = g else { return XCTFail("expected ellipse, got \(g)") }
        XCTAssertEqual(b.size.width, b.size.height, accuracy: 0.001, "near-circles become exact circles")
        XCTAssertEqual(b.size.width, 160, accuracy: 5)
        XCTAssertEqual(b.center.x, 100, accuracy: 3)
    }

    func testRotatedEllipse() throws {
        let pts = jitter(ellipsePoints(center: .zero, rx: 120, ry: 60, rotation: .pi / 6), 2)
        let (g, _) = try XCTUnwrap(recognizeShape(pts))
        guard case let .ellipse(b) = g else { return XCTFail("expected ellipse, got \(g)") }
        XCTAssertEqual(b.size.width, 240, accuracy: 6)
        XCTAssertEqual(b.size.height, 120, accuracy: 6)
        XCTAssertEqual(Geometry.angleDifference(b.rotation, .pi / 6), 0, accuracy: 0.05)
    }

    func testOvershootingCircleIsClosed() throws {
        let pts = jitter(ellipsePoints(center: .zero, rx: 80, ry: 80, count: 120, sweep: 1.15), 2)
        let (g, _) = try XCTUnwrap(recognizeShape(pts))
        guard case .ellipse = g else { return XCTFail("expected ellipse, got \(g)") }
    }

    func testAxisAlignedRectangle() throws {
        let pts = jitter(trace([.zero, CGPoint(x: 200, y: 0), CGPoint(x: 200, y: 120), CGPoint(x: 0, y: 120)]), 2)
        let (g, _) = try XCTUnwrap(recognizeShape(pts))
        guard case let .rectangle(b) = g else { return XCTFail("expected rectangle, got \(g)") }
        XCTAssertEqual(b.rotation, 0, accuracy: 0.0001)
        XCTAssertEqual(b.size.width, 200, accuracy: 5)
        XCTAssertEqual(b.size.height, 120, accuracy: 5)
    }

    func testRotatedRectangleKeepsRotation() throws {
        let verts = [CGPoint.zero, CGPoint(x: 200, y: 0), CGPoint(x: 200, y: 120), CGPoint(x: 0, y: 120)]
            .map { $0.rotated(by: 20 * .pi / 180) }
        let (g, _) = try XCTUnwrap(recognizeShape(jitter(trace(verts), 2)))
        guard case let .rectangle(b) = g else { return XCTFail("expected rectangle, got \(g)") }
        XCTAssertEqual(b.rotation * 180 / .pi, 20, accuracy: 2)
    }

    func testSquareIsRegularized() throws {
        let pts = jitter(trace([.zero, CGPoint(x: 150, y: 0), CGPoint(x: 152, y: 148), CGPoint(x: 0, y: 150)]), 2)
        let (g, _) = try XCTUnwrap(recognizeShape(pts))
        guard case let .rectangle(b) = g else { return XCTFail("expected rectangle, got \(g)") }
        XCTAssertEqual(b.size.width, b.size.height, accuracy: 0.001)
    }

    func testTriangle() throws {
        let pts = jitter(trace([.zero, CGPoint(x: 200, y: 0), CGPoint(x: 90, y: -150)]), 2)
        let (g, _) = try XCTUnwrap(recognizeShape(pts))
        guard case let .polygon(v, closed) = g else { return XCTFail("expected polygon, got \(g)") }
        XCTAssertTrue(closed)
        XCTAssertEqual(v.count, 3)
    }

    func testRightTriangleGetsExactRightAngle() throws {
        let pts = jitter(trace([.zero, CGPoint(x: 0, y: 150), CGPoint(x: 160, y: 150)]), 2)
        let (g, _) = try XCTUnwrap(recognizeShape(pts))
        guard case let .polygon(v, _) = g, v.count == 3 else { return XCTFail("expected triangle, got \(g)") }
        let angles = (0..<3).map { i -> CGFloat in
            let a = v[(i + 2) % 3] - v[i], b = v[(i + 1) % 3] - v[i]
            return Geometry.angleDifference(a.angle, b.angle)
        }
        XCTAssertTrue(angles.contains { abs($0 - .pi / 2) < 0.001 }, "angles: \(angles)")
    }

    func testHexagon() throws {
        let verts = (0..<6).map { CGPoint.unit(angle: CGFloat($0) * .pi / 3) * 100 }
        let (g, _) = try XCTUnwrap(recognizeShape(jitter(trace(verts), 1.5)))
        guard case let .polygon(v, true) = g else { return XCTFail("expected polygon, got \(g)") }
        XCTAssertEqual(v.count, 6)
    }

    func testSingleStrokeArrow() throws {
        let pts = jitter(trace([.zero, CGPoint(x: 200, y: 0), CGPoint(x: 180, y: -15), CGPoint(x: 200, y: 0), CGPoint(x: 180, y: 15)],
                               closed: false), 1)
        let (g, arrows) = try XCTUnwrap(recognizeShape(pts))
        guard case let .line(s, e) = g else { return XCTFail("expected arrow, got \(g)") }
        XCTAssertTrue(arrows.end)
        XCTAssertEqual(e.x, 200, accuracy: 4)
        XCTAssertEqual(s.x, 0, accuracy: 4)
    }

    func testOpenPolyline() throws {
        let pts = jitter(trace([.zero, CGPoint(x: 0, y: 150), CGPoint(x: 150, y: 150)], closed: false), 1.5)
        let (g, _) = try XCTUnwrap(recognizeShape(pts))
        guard case let .polygon(v, closed) = g else { return XCTFail("expected polyline, got \(g)") }
        XCTAssertFalse(closed)
        XCTAssertEqual(v.count, 3)
        // Segments snap to the axes.
        XCTAssertEqual(v[0].x, v[1].x, accuracy: 0.5)
        XCTAssertEqual(v[1].y, v[2].y, accuracy: 0.5)
    }

    func testSmoothCurve() throws {
        let pts = jitter(stride(from: 0, to: 250, by: 2).map { CGPoint(x: CGFloat($0), y: 40 * sin(CGFloat($0) / 40)) }, 1)
        let (g, _) = try XCTUnwrap(recognizeShape(pts))
        guard case .curve = g else { return XCTFail("expected curve, got \(g)") }
    }

    func testComplexHandwritingIsNotAShape() {
        // A long, loopy cursive-like stroke should stay ink.
        var pts: [CGPoint] = []
        for i in 0..<400 {
            let t = CGFloat(i) / 20
            pts.append(CGPoint(x: t * 12 + 5 * sin(t * 2.3), y: 12 * cos(t * 3.1) + 4 * sin(t * 7)))
        }
        XCTAssertNil(recognizer.recognize(pts))
    }

    func testEndpointSnapsToExistingShape() throws {
        var ctx = RecognitionContext()
        ctx.snapPoints = [CGPoint(x: 203, y: 40)]
        ctx.snapTolerance = 10
        guard case let .shape(.line(_, e), _)? = recognizer.recognize(trace([.zero, CGPoint(x: 198, y: 37)], closed: false), context: ctx) else {
            return XCTFail("expected line")
        }
        XCTAssertEqual(e, CGPoint(x: 203, y: 40))
    }

    func testVShapeAddsArrowHeadToExistingLine() {
        var ctx = RecognitionContext()
        let lineID = UUID()
        ctx.lines = [(lineID, CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0))]
        let v = trace([CGPoint(x: 185, y: -14), CGPoint(x: 200, y: 0), CGPoint(x: 185, y: 14)], closed: false)
        guard case let .addArrowHead(id, atEnd)? = recognizer.recognize(v, context: ctx) else {
            return XCTFail("expected arrow head upgrade")
        }
        XCTAssertEqual(id, lineID)
        XCTAssertTrue(atEnd)
    }
}

/// Deterministic generator so tests are reproducible.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }

    mutating func nextUInt() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func next(in range: ClosedRange<CGFloat>) -> CGFloat {
        let unit = CGFloat(nextUInt() % 1_000_000) / 1_000_000
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
