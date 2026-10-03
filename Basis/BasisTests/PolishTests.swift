import CoreGraphics
import XCTest
@testable import Basis

@MainActor
final class PolishTests: XCTestCase {
    private var root: URL!
    private var store: DocumentStore!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = DocumentStore(rootURL: root)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeEditor(pages: Int = 3, background: PageBackground = PageBackground()) -> EditorModel {
        let data = (0..<pages).map { _ in PageData(size: PaperSize.letter.size(for: .portrait), background: background) }
        let doc = DocumentModel(id: UUID(), title: "Test", createdAt: Date(), modifiedAt: Date(), pages: data,
                                toolSettings: ToolSettings(), viewState: ViewState(), assetsURL: root)
        return EditorModel(document: doc, store: store)
    }

    func testSectionsAreUndoable() {
        let editor = makeEditor()
        editor.setSection("Kinematics", at: 0)
        editor.setSection("Dynamics", at: 2)
        XCTAssertEqual(editor.sections.map(\.title), ["Kinematics", "Dynamics"])
        XCTAssertEqual(editor.section(containing: 1)?.title, "Kinematics")
        XCTAssertEqual(editor.section(containing: 2)?.title, "Dynamics")
        editor.setSection("  ", at: 2)          // blank removes
        XCTAssertEqual(editor.sections.count, 1)
        editor.undo()
        XCTAssertEqual(editor.sections.count, 2)
        // Page settings applied to all pages keep each page's section.
        editor.applyPageSettings(size: PaperSize.a4.size(for: .portrait), background: PageBackground(template: .cornell), toAllPages: true)
        XCTAssertEqual(editor.sections.map(\.title), ["Kinematics", "Dynamics"])
        XCTAssertEqual(editor.document.pages[1].background.template, .cornell)
        // New pages don't copy the section.
        editor.addPage(after: 0, scroll: false)
        XCTAssertNil(editor.document.pages[1].background.section)
    }

    func testEndlessPageGrows() {
        var bg = PageBackground()
        bg.autoExtends = true
        let editor = makeEditor(pages: 1, background: bg)
        let page = editor.document.pages[0]
        let height = page.size.height
        let stroke = CanvasElement.stroke(Stroke(points: [InkPoint(location: CGPoint(x: 50, y: height - 100)),
                                                          InkPoint(location: CGPoint(x: 150, y: height - 90))],
                                                 style: PenPreset.ballpoint.style))
        editor.history.perform(ElementsEdit.add([stroke], to: page, name: "Ink"))
        XCTAssertGreaterThan(page.size.height, height)
        XCTAssertEqual(page.size.width, PaperSize.letter.size(for: .portrait).width)

        // Normal pages never grow.
        let fixed = makeEditor(pages: 1)
        let p2 = fixed.document.pages[0]
        fixed.history.perform(ElementsEdit.add([stroke], to: p2, name: "Ink"))
        XCTAssertEqual(p2.size.height, height)
    }

    func testOldBackgroundsDecode() throws {
        let json = #"{"color":{"r":1,"g":1,"b":1,"a":1},"template":"ruled","spacing":24}"#
        let bg = try JSONDecoder().decode(PageBackground.self, from: Data(json.utf8))
        XCTAssertNil(bg.section)
        XCTAssertNil(bg.autoExtends)
        XCTAssertEqual(bg.template, .ruled)
    }

    func testEveryTemplateDraws() throws {
        let renderer = PageRenderer(assetsURL: root)
        let size = CGSize(width: 300, height: 400)
        for template in PageTemplate.allCases {
            let ctx = try XCTUnwrap(CGContext(data: nil, width: 300, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            renderer.drawBackground(PageBackground(template: template), pageSize: size, in: ctx,
                                    clip: CGRect(x: 30, y: 40, width: 200, height: 250))
        }
    }

    func testSearchablePagesIncludeTextCardsAndSections() throws {
        var bg = PageBackground()
        bg.section = "Lab 4"
        let id = try store.create(title: "Physics", pageSize: CGSize(width: 600, height: 800), background: bg)
        // Add a second page with typed text and a calculation card.
        let pkg = store.packageURL(id)
        let block = CalculationBlock.expression("2 + 2")
        var page = PageData(size: CGSize(width: 600, height: 800), background: PageBackground())
        page.elements = [
            .text(TextElement(text: "Momentum is conserved", style: TextStyle(), box: BoxGeometry(rect: CGRect(x: 0, y: 0, width: 200, height: 20)))),
            .text(TextElement(text: "2 + 2 = 4", style: TextStyle(), box: BoxGeometry(rect: .zero), calculation: block)),
        ]
        let first = try XCTUnwrap(store.searchablePages().first)
        let manifest = DocumentManifest(id: id, title: "Physics", createdAt: Date(), modifiedAt: Date(),
                                        pageIDs: [UUID(), page.id], firstPageSize: page.size,
                                        toolSettings: ToolSettings(), viewState: ViewState())
        XCTAssertEqual(first.section, "Lab 4")
        try DocumentStore.write(DocumentModel.Snapshot(manifest: manifest, dirtyPages: [page], livePageIDs: [page.id]), to: pkg)

        let pages = store.searchablePages()
        let hit = try XCTUnwrap(pages.first { $0.text.contains("Momentum") })
        XCTAssertEqual(hit.pageIndex, 1)
        XCTAssertEqual(hit.title, "Physics")
        XCTAssertTrue(hit.text.contains("2 + 2 = 4"))
    }

    func testSnippet() {
        let text = String(repeating: "a", count: 100) + " Bernoulli equation " + String(repeating: "b", count: 100)
        let s = SearchView.snippet(text, around: "bernoulli", radius: 10)
        XCTAssertTrue(s.hasPrefix("…"))
        XCTAssertTrue(s.hasSuffix("…"))
        XCTAssertTrue(s.contains("Bernoulli"))
        XCTAssertEqual(SearchView.snippet("short\ntext", around: "zzz"), "short  text")
    }

    func testImportMergesCalculatorData() throws {
        let dir = root.appendingPathComponent("calc")
        let source = CalculatorStore(directory: dir.appendingPathComponent("a"))
        source.save(Formula(name: "Mine", expression: "y = 3x"))
        _ = try source.evaluate("k = 7")
        source.save(DataTable.blank(name: "Trial"))
        source.flush()
        let url = try XCTUnwrap(source.exportData())

        let target = CalculatorStore(directory: dir.appendingPathComponent("b"))
        let message = try target.importData(Data(contentsOf: url))
        XCTAssertTrue(message.hasPrefix("Imported"), message)
        XCTAssertEqual(target.userFormulas.map(\.name), ["Mine"])
        XCTAssertEqual(target.variables.map(\.name), ["k"])
        XCTAssertEqual(target.tables.map(\.name), ["Trial"])
        XCTAssertEqual(target.history.count, 1)
        // Importing again replaces instead of duplicating.
        try target.importData(Data(contentsOf: url))
        XCTAssertEqual(target.userFormulas.count, 1)
        XCTAssertEqual(target.history.count, 1)
        XCTAssertThrowsError(try target.importData(Data("{}".utf8)))
        XCTAssertThrowsError(try target.importData(Data("nonsense".utf8)))
    }
}

final class HandwritingMathTests: XCTestCase {
    func testNormalizeCommonMisreadings() {
        XCTAssertEqual(MathRecognizer.normalize("2 x 3"), "2 × 3")
        XCTAssertEqual(MathRecognizer.normalize("12X4="), "12×4")
        XCTAssertEqual(MathRecognizer.normalize("1O + 5 = ?"), "10 + 5")
        XCTAssertEqual(MathRecognizer.normalize("l2 — 4"), "12 - 4")
        XCTAssertEqual(MathRecognizer.normalize("8 ÷ 2"), "8 / 2")
        XCTAssertEqual(MathRecognizer.normalize("2+3=5"), "2+3")
        XCTAssertEqual(MathRecognizer.normalize("m = 5"), "m = 5")      // assignment kept
        XCTAssertEqual(MathRecognizer.normalize("2x + 1"), "2x + 1")    // x as a variable
        XCTAssertEqual(MathRecognizer.normalize("cos(0)"), "cos(0)")
        XCTAssertEqual(MathRecognizer.normalize("log(100)"), "log(100)")
    }

    func testPicksAReadingTheCalculatorUnderstands() {
        let engine = CalculatorEngine()
        let lines = [["2 +", "2 + 3", "2+3"], ["5 x 4 ="]]
        XCTAssertEqual(MathRecognizer.expression(from: lines, engine: engine), "2 + 3\n5 × 4")
        XCTAssertNil(MathRecognizer.expression(from: [], engine: engine))
        // Normalized readings evaluate.
        XCTAssertEqual(try engine.evaluateLine("5 × 4").value, 20)
    }

    func testRendersSelectedInk() {
        let ink = CanvasElement.stroke(Stroke(points: [InkPoint(location: CGPoint(x: 10, y: 10)), InkPoint(location: CGPoint(x: 60, y: 40))],
                                              style: PenPreset.ballpoint.style))
        let image = MathRecognizer.image(of: [ink], renderer: PageRenderer(assetsURL: FileManager.default.temporaryDirectory))
        XCTAssertNotNil(image)
        XCTAssertNil(MathRecognizer.image(of: [], renderer: PageRenderer(assetsURL: FileManager.default.temporaryDirectory)))
    }
}

@MainActor
final class WhiteboardTests: XCTestCase {
    func testWhiteboardGrowsRight() {
        var bg = PageBackground(template: .grid)
        bg.autoExtends = true
        let size = PaperSize.whiteboard.size(for: .portrait)
        let doc = DocumentModel(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(),
                                pages: [PageData(size: size, background: bg)], toolSettings: ToolSettings(), viewState: ViewState(),
                                assetsURL: FileManager.default.temporaryDirectory)
        let editor = EditorModel(document: doc, store: DocumentStore(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let page = doc.pages[0]
        let ink = CanvasElement.stroke(Stroke(points: [InkPoint(location: CGPoint(x: size.width - 50, y: 100)),
                                                       InkPoint(location: CGPoint(x: size.width - 20, y: 120))],
                                              style: PenPreset.ballpoint.style))
        editor.history.perform(ElementsEdit.add([ink], to: page, name: "Ink"))
        XCTAssertGreaterThan(page.size.width, size.width)
        XCTAssertEqual(page.size.height, size.height)   // content is near the top
    }

    func testChoosingWhiteboardTurnsOnEndlessPage() {
        var format = PageFormat()
        XCTAssertFalse(format.autoExtends)
        format.paperID = PaperSize.whiteboard.id
        XCTAssertTrue(format.autoExtends)
        XCTAssertEqual(format.background.autoExtends, true)
    }
}

final class AutoMathTests: XCTestCase {
    func testQuestionsEndingInEquals() {
        XCTAssertEqual(AutoMathController.question(from: ["6+8="]), "6+8")
        XCTAssertEqual(AutoMathController.question(from: ["4 + 5 = ?"]), "4 + 5")
        XCTAssertEqual(AutoMathController.question(from: ["12 x 3 ="]), "12 × 3")
        XCTAssertEqual(AutoMathController.question(from: ["6+8", "6+8="]), "6+8")   // later candidate
        XCTAssertNil(AutoMathController.question(from: ["6+8"]))          // no "=" yet
        XCTAssertNil(AutoMathController.question(from: ["x ="]))          // nothing to compute
        XCTAssertNil(AutoMathController.question(from: ["2+3=5"]))        // already answered
        XCTAssertNil(AutoMathController.question(from: []))
    }

    private func stroke(_ x: CGFloat, _ y: CGFloat, w: CGFloat = 20, h: CGFloat = 30) -> Stroke {
        Stroke(points: [InkPoint(location: CGPoint(x: x, y: y)), InkPoint(location: CGPoint(x: x + w, y: y + h))],
               style: PenPreset.ballpoint.style)
    }

    func testLineGrouping() {
        // "6 + 8 =" on one line, "4 + 5" on the line below, a far-away note.
        let six = stroke(100, 100), plus = stroke(135, 108, w: 18, h: 16), eight = stroke(165, 100)
        let eq = stroke(200, 112, w: 18, h: 6)
        let below = [stroke(100, 160), stroke(135, 168, w: 18, h: 16)]
        let far = stroke(600, 100)
        let line = AutoMathController.line(containing: eq, in: [six, plus, eight, eq, far] + below)
        XCTAssertEqual(Set(line.map(\.id)), Set([six, plus, eight, eq].map(\.id)))
        XCTAssertEqual(line.first?.id, six.id)   // left to right
    }

    func testLongScrollTurnsOnEndlessPage() {
        var format = PageFormat()
        format.paperID = PaperSize.longScroll.id
        XCTAssertTrue(format.autoExtends)
    }
}
