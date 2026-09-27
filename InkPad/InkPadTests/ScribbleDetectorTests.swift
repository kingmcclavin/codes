import CoreGraphics
import XCTest
@testable import InkPad

final class ScribbleDetectorTests: XCTestCase {
    private let detector = ScribbleDetector()

    private func timed(_ pts: [CGPoint], duration: TimeInterval) -> (points: [CGPoint], times: [TimeInterval]) {
        (pts, pts.indices.map { duration * Double($0) / Double(max(pts.count - 1, 1)) })
    }

    /// Horizontal back-and-forth passes drifting slowly downward.
    private func backAndForth(passes: Int, width: CGFloat, height: CGFloat, n: Int = 40) -> [CGPoint] {
        var pts: [CGPoint] = []
        for k in 0..<passes {
            for j in 0..<n {
                let f = CGFloat(j) / CGFloat(n)
                let x = k % 2 == 0 ? width * f : width * (1 - f)
                pts.append(CGPoint(x: x, y: height * CGFloat(k * n + j) / CGFloat(passes * n)))
            }
        }
        return pts
    }

    /// Cursive-like humps ("mmmm").
    private func humps(count: Int, width: CGFloat, height: CGFloat, n: Int = 30) -> [CGPoint] {
        (0..<count).flatMap { c in
            (0..<n).map { j -> CGPoint in
                let t = CGFloat(j) / CGFloat(n)
                return CGPoint(x: CGFloat(c) * width + t * width, y: -height * abs(sin(t * .pi)))
            }
        }
    }

    func testFastScribbleIsDetected() {
        let s = timed(backAndForth(passes: 8, width: 120, height: 15), duration: 0.8)
        XCTAssertTrue(detector.isScribble(points: s.points, times: s.times, zoom: 1))
    }

    func testShortScribbleIsDetected() {
        let s = timed(backAndForth(passes: 5, width: 90, height: 10), duration: 0.5)
        XCTAssertTrue(detector.isScribble(points: s.points, times: s.times, zoom: 1))
    }

    func testCursiveHandwritingIsNotAScribble() {
        let s = timed(humps(count: 12, width: 10, height: 25), duration: 1.0)
        XCTAssertFalse(detector.isScribble(points: s.points, times: s.times, zoom: 1))
    }

    func testSlowShadingIsNotAScribble() {
        let s = timed(backAndForth(passes: 6, width: 40, height: 40), duration: 1.2)
        XCTAssertFalse(detector.isScribble(points: s.points, times: s.times, zoom: 1))
    }

    func testStraightLineAndCircleAreNotScribbles() {
        let line = timed(stride(from: 0, to: 200, by: 2).map { CGPoint(x: CGFloat($0), y: 0) }, duration: 0.2)
        XCTAssertFalse(detector.isScribble(points: line.points, times: line.times, zoom: 1))
        let circle = timed((0...80).map { CGPoint.unit(angle: CGFloat($0) / 80 * 2 * .pi) * 60 }, duration: 0.4)
        XCTAssertFalse(detector.isScribble(points: circle.points, times: circle.times, zoom: 1))
    }

    func testReversalCounting() {
        XCTAssertEqual(ScribbleDetector.reversals([0, 10, 0, 10, 0], hysteresis: 4), 3)
        XCTAssertEqual(ScribbleDetector.reversals([0, 1, 0, 1, 0, 1], hysteresis: 4), 0, "wiggles below hysteresis are ignored")
    }

    @MainActor
    func testScribbleEraserRequiresContentUnderneath() {
        let page = PageStore(data: PageData(size: CGSize(width: 400, height: 400), background: PageBackground()))
        let scribble = backAndForth(passes: 8, width: 120, height: 15).map { $0 + CGPoint(x: 50, y: 50) }
        XCTAssertNil(ScribbleEraser.command(for: scribble, on: page, mode: .strokes, tolerance: 3))

        // A "word" under the scribble.
        let word = Stroke(points: stride(from: 0, to: 110, by: 2).map {
            InkPoint(location: CGPoint(x: 55 + CGFloat($0), y: 57 + 4 * sin(CGFloat($0) / 4)))
        }, style: PenPreset.ballpoint.style)
        let unrelated = Stroke(points: [InkPoint(location: CGPoint(x: 50, y: 300)), InkPoint(location: CGPoint(x: 200, y: 300))],
                               style: PenPreset.ballpoint.style)
        page.insert(.stroke(word))
        page.insert(.stroke(unrelated))
        guard let edit = ScribbleEraser.command(for: scribble, on: page, mode: .strokes, tolerance: 3) as? ElementsEdit else {
            return XCTFail("expected an erase")
        }
        XCTAssertEqual(edit.removed.map(\.element.id), [word.id])
    }
}
