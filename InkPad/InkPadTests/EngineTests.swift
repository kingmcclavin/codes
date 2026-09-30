import CoreGraphics
import XCTest
@testable import InkPad

@MainActor
final class HistoryTests: XCTestCase {
    private func makeDocument(pages: Int = 1) -> DocumentModel {
        let data = (0..<pages).map { _ in PageData(size: PaperSize.letter.size(for: .portrait), background: PageBackground()) }
        return DocumentModel(id: UUID(), title: "Test", createdAt: Date(), modifiedAt: Date(), pages: data,
                             toolSettings: ToolSettings(), viewState: ViewState(),
                             assetsURL: FileManager.default.temporaryDirectory)
    }

    private func stroke(_ x: CGFloat) -> CanvasElement {
        .stroke(Stroke(points: [InkPoint(location: CGPoint(x: x, y: 10)), InkPoint(location: CGPoint(x: x + 50, y: 10))],
                       style: PenPreset.ballpoint.style))
    }

    func testOneStrokeIsOneUndoStep() {
        let doc = makeDocument()
        let history = History(document: doc)
        let page = doc.pages[0]
        history.perform(ElementsEdit.add([stroke(0)], to: page, name: "Ink"))
        history.perform(ElementsEdit.add([stroke(100)], to: page, name: "Ink"))
        XCTAssertEqual(page.count, 2)
        history.undo()
        XCTAssertEqual(page.count, 1)
        history.undo()
        XCTAssertEqual(page.count, 0)
        XCTAssertFalse(history.canUndo)
        history.redo()
        history.redo()
        XCTAssertEqual(page.count, 2)
        XCTAssertFalse(history.canRedo)
    }

    func testNewActionClearsRedo() {
        let doc = makeDocument()
        let history = History(document: doc)
        let page = doc.pages[0]
        history.perform(ElementsEdit.add([stroke(0)], to: page, name: "Ink"))
        history.undo()
        history.perform(ElementsEdit.add([stroke(10)], to: page, name: "Ink"))
        XCTAssertFalse(history.canRedo)
    }

    func testRemovalRestoresZOrder() {
        let doc = makeDocument()
        let history = History(document: doc)
        let page = doc.pages[0]
        let a = stroke(0), b = stroke(10), c = stroke(20)
        history.perform(ElementsEdit.add([a, b, c], to: page, name: "Ink"))
        history.perform(ElementsEdit.remove([a.id, c.id], from: page, name: "Delete"))
        XCTAssertEqual(page.allElements.map(\.id), [b.id])
        history.undo()
        XCTAssertEqual(page.allElements.map(\.id), [a.id, b.id, c.id])
    }

    func testPartialEraseIsOneUndoStep() {
        let doc = makeDocument()
        let history = History(document: doc)
        let page = doc.pages[0]
        let s = Stroke(points: stride(from: 0, through: 200, by: 5).map { InkPoint(location: CGPoint(x: CGFloat($0), y: 100)) },
                       style: PenPreset.fine.style)
        history.perform(ElementsEdit.add([.stroke(s)], to: page, name: "Ink"))

        // Simulate the eraser: incremental edits applied immediately, recorded once.
        var applied: [EditCommand] = []
        for x in [60.0, 140.0] as [CGFloat] {
            for e in page.allElements {
                guard case let .stroke(st) = e, let pieces = ErasureEngine.erase(st, along: [CGPoint(x: x, y: 90), CGPoint(x: x, y: 110)], radius: 6),
                      let idx = page.index(of: e.id) else { continue }
                let edit = ElementsEdit.replace(e, at: idx, with: pieces.map { .stroke($0) }, page: page, name: "Erase")
                edit.apply(to: doc)
                applied.append(edit)
            }
        }
        history.record(CompositeCommand(name: "Erase", commands: applied))
        XCTAssertEqual(page.count, 3)
        history.undo()
        XCTAssertEqual(page.allElements.map(\.id), [s.id])
        history.redo()
        XCTAssertEqual(page.count, 3)
    }

    func testTransformUndo() {
        let doc = makeDocument()
        let history = History(document: doc)
        let page = doc.pages[0]
        let e = stroke(0)
        history.perform(ElementsEdit.add([e], to: page, name: "Ink"))
        let moved = e.transformed(by: CGAffineTransform(translationX: 30, y: 40))
        history.perform(ElementsEdit.update([(e, moved)], page: page, name: "Move"))
        XCTAssertEqual(page.element(e.id)?.bounds.minX ?? 0, e.bounds.minX + 30, accuracy: 0.01)
        history.undo()
        XCTAssertEqual(page.element(e.id)?.bounds.minX ?? 0, e.bounds.minX, accuracy: 0.01)
    }

    func testPageCommands() {
        let doc = makeDocument(pages: 2)
        let history = History(document: doc)
        let firstID = doc.pages[0].id
        history.perform(MovePageCommand(from: 0, to: 1))
        XCTAssertEqual(doc.pages[1].id, firstID)
        history.undo()
        XCTAssertEqual(doc.pages[0].id, firstID)

        history.perform(DeletePageCommand(page: doc.pages[0].pageData(), index: 0))
        XCTAssertEqual(doc.pages.count, 1)
        history.undo()
        XCTAssertEqual(doc.pages.count, 2)
        XCTAssertEqual(doc.pages[0].id, firstID)
    }

    func testReorderToFrontAndBack() {
        let doc = makeDocument()
        let history = History(document: doc)
        let page = doc.pages[0]
        let a = stroke(0), b = stroke(10), c = stroke(20)
        history.perform(ElementsEdit.add([a, b, c], to: page, name: "Ink"))
        // Bring a & b to front (as CanvasViewController.arrangeSelection does).
        history.perform(ReorderElementsCommand(name: "Front", pageID: page.id, moves: [(a.id, 0, 2), (b.id, 0, 2)]))
        XCTAssertEqual(page.allElements.map(\.id), [c.id, a.id, b.id])
        history.undo()
        XCTAssertEqual(page.allElements.map(\.id), [a.id, b.id, c.id])
    }
}

final class ErasureEngineTests: XCTestCase {
    private func line(from x0: CGFloat, to x1: CGFloat) -> Stroke {
        Stroke(points: stride(from: x0, through: x1, by: 10).map { InkPoint(location: CGPoint(x: $0, y: 0)) },
               style: PenPreset.fine.style)
    }

    func testEraseMiddleSplitsStroke() throws {
        let pieces = try XCTUnwrap(ErasureEngine.erase(line(from: 0, to: 100), along: [CGPoint(x: 50, y: -20), CGPoint(x: 50, y: 20)], radius: 5))
        XCTAssertEqual(pieces.count, 2)
        XCTAssertLessThan(pieces[0].bounds.maxX, 50)
        XCTAssertGreaterThan(pieces[1].bounds.minX, 50)
    }

    func testUntouchedStrokeReturnsNil() {
        XCTAssertNil(ErasureEngine.erase(line(from: 0, to: 100), along: [CGPoint(x: 50, y: 30), CGPoint(x: 60, y: 30)], radius: 5))
    }

    func testFullyCoveredStrokeDisappears() throws {
        let pieces = try XCTUnwrap(ErasureEngine.erase(line(from: 0, to: 20),
                                                       inside: [CGPoint(x: -10, y: -10), CGPoint(x: 30, y: -10), CGPoint(x: 30, y: 10), CGPoint(x: -10, y: 10)]))
        XCTAssertTrue(pieces.isEmpty)
    }

    func testDensifyKeepsEndpoints() {
        let pts = [InkPoint(location: .zero, force: 0), InkPoint(location: CGPoint(x: 10, y: 0), force: 1)]
        let dense = ErasureEngine.densify(pts, spacing: 1)
        XCTAssertEqual(dense.first?.location, .zero)
        XCTAssertEqual(dense.last?.location, CGPoint(x: 10, y: 0))
        XCTAssertGreaterThanOrEqual(dense.count, 10)
        XCTAssertEqual(dense[dense.count / 2].force, 0.5, accuracy: 0.1, "pressure is interpolated")
    }
}

final class ModelTests: XCTestCase {
    func testStrokeCodingRoundTrip() throws {
        let s = Stroke(points: (0..<50).map { InkPoint(location: CGPoint(x: CGFloat($0) * 1.5, y: sin(CGFloat($0))), force: 0.3,
                                                       altitude: 1.1, azimuth: 0.4, t: Double($0) / 240) },
                       style: PenPreset.fountain.style)
        let data = try JSONEncoder().encode(CanvasElement.stroke(s))
        guard case let .stroke(back) = try JSONDecoder().decode(CanvasElement.self, from: data) else { return XCTFail() }
        XCTAssertEqual(back.id, s.id)
        XCTAssertEqual(back.points, s.points)
        XCTAssertEqual(back.style, s.style)
    }

    func testShapeAndTextCoding() throws {
        let shape = CanvasElement.shape(ShapeElement(geometry: .rectangle(BoxGeometry(center: CGPoint(x: 10, y: 20), size: CGSize(width: 30, height: 40), rotation: 0.3)),
                                                     style: ShapeStyle(fillColor: .white), arrows: .none))
        let text = CanvasElement.text(TextElement(text: "∫ f(x) dx", style: TextStyle(), box: BoxGeometry(rect: CGRect(x: 0, y: 0, width: 100, height: 20))))
        let data = try JSONEncoder().encode(PageData(size: CGSize(width: 100, height: 100), background: PageBackground(template: .grid), elements: [shape, text]))
        let page = try JSONDecoder().decode(PageData.self, from: data)
        XCTAssertEqual(page.elements.map(\.id), [shape.id, text.id])
        XCTAssertEqual(page.background.template, .grid)
    }

    func testToolSettingsDecodeIsTolerant() throws {
        let json = #"{"currentTool":"eraser","scribbleToErase":false,"futureSetting":42}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(ToolSettings.self, from: json)
        XCTAssertEqual(s.currentTool, .eraser)
        XCTAssertFalse(s.scribbleToErase)
        XCTAssertEqual(s.pen, ToolSettings().pen)
    }

    func testBoxTransform() {
        let box = BoxGeometry(center: CGPoint(x: 10, y: 10), size: CGSize(width: 20, height: 10), rotation: 0)
        let rotated = box.applying(CGAffineTransform(rotationAngle: .pi / 2))
        XCTAssertEqual(rotated.center.x, -10, accuracy: 1e-6)
        XCTAssertEqual(rotated.center.y, 10, accuracy: 1e-6)
        XCTAssertEqual(rotated.rotation, .pi / 2, accuracy: 1e-6)
        XCTAssertEqual(rotated.size.width, 20, accuracy: 1e-6)
        let scaled = box.applying(CGAffineTransform(scaleX: 2, y: 3))
        XCTAssertEqual(scaled.size.width, 40, accuracy: 1e-6)
        XCTAssertEqual(scaled.size.height, 30, accuracy: 1e-6)
    }

    func testPaperSizes() {
        XCTAssertEqual(PaperSize.a4.size(for: .landscape).width, 841.89, accuracy: 0.01)
        XCTAssertEqual(LengthUnit.millimeters.toPoints(210), 595.28, accuracy: 0.01)
        XCTAssertEqual(PaperSize.matching(CGSize(width: 792, height: 612))?.paper.id, "letter")
    }

    func testLongScrollPresetAndDarkGreyPaper() {
        XCTAssertEqual(PaperSize.find("long-455x2500")?.size(for: .portrait), CGSize(width: 455, height: 2500))
        XCTAssertTrue(PageBackground(color: .paperDarkGray).isDark, "dark grey paper gets light template lines")
        XCTAssertEqual(PageFormat(size: CGSize(width: 455, height: 2500), background: PageBackground(color: .paperDarkGray)).backgroundChoice,
                       .darkGray)
    }

    func testSpatialGridQuery() {
        var grid = SpatialGrid(cellSize: 100)
        let a = UUID(), b = UUID()
        grid.insert(a, bounds: CGRect(x: 10, y: 10, width: 20, height: 20))
        grid.insert(b, bounds: CGRect(x: 450, y: 450, width: 300, height: 20))
        XCTAssertEqual(grid.query(CGRect(x: 0, y: 0, width: 50, height: 50)), [a])
        XCTAssertEqual(grid.query(CGRect(x: 700, y: 460, width: 5, height: 5)), [b])
        grid.remove(b)
        XCTAssertTrue(grid.query(CGRect(x: 700, y: 460, width: 5, height: 5)).isEmpty)
    }

    func testStrokePathIsFillableAndBounded() {
        let s = Stroke(points: (0..<30).map { InkPoint(location: CGPoint(x: CGFloat($0) * 3, y: 0), force: CGFloat($0) / 30) },
                       style: PenPreset.fountain.style)
        let path = StrokePathBuilder.path(for: s)
        XCTAssertFalse(path.isEmpty)
        XCTAssertTrue(s.bounds.contains(path.boundingBoxOfPath.insetBy(dx: 0.5, dy: 0.5)))
        XCTAssertTrue(path.contains(CGPoint(x: 45, y: 0)))
    }
}
