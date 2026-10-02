import CoreGraphics
import XCTest
@testable import InkPad

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
