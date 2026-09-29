import UIKit
import XCTest
@testable import InkPad

final class PDFImportTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    /// A two-page PDF: Letter portrait, then A4 landscape.
    private func makePDF() throws -> URL {
        let url = dir.appendingPathComponent("Lecture Notes.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 100, y: 100, width: 50, height: 50))
            ctx.beginPage(withBounds: CGRect(x: 0, y: 0, width: 842, height: 595), pageInfo: [:])
        }
        return url
    }

    func testPagesKeepPDFSizesAndReferenceTheCopiedFile() throws {
        let assets = dir.appendingPathComponent("assets")
        let pages = try PDFImporter.pages(from: try makePDF(), into: assets)
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].size, CGSize(width: 612, height: 792))
        XCTAssertEqual(pages[1].size, CGSize(width: 842, height: 595))
        XCTAssertEqual(pages.map { $0.background.pdf?.pageIndex }, [0, 1])
        let asset = try XCTUnwrap(pages[0].background.pdf?.assetName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: assets.appendingPathComponent(asset).path))
    }

    func testRendererDrawsPDFBackground() throws {
        let assets = dir.appendingPathComponent("assets")
        let page = try XCTUnwrap(try PDFImporter.pages(from: try makePDF(), into: assets).first)
        let renderer = PageRenderer(assetsURL: assets)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard   // 8-bit BGRA
        let image = UIGraphicsImageRenderer(size: page.size, format: format).image { ctx in
            renderer.drawPage(page, in: ctx.cgContext)
        }
        // The red square from the PDF must show up at the same (top-left based) position.
        let pixel = try XCTUnwrap(image.cgImage?.dataProvider?.data as Data?)
        let bytesPerRow = image.cgImage!.bytesPerRow
        let offset = 125 * bytesPerRow + 125 * 4
        XCTAssertGreaterThan(pixel[offset + 2], 200, "red channel (BGRA)")
        XCTAssertLessThan(pixel[offset], 60, "blue channel")
    }

    @MainActor
    func testCreateNotebookFromPDF() throws {
        let store = DocumentStore(rootURL: dir.appendingPathComponent("library"))
        let id = try store.createFromPDF(try makePDF())
        XCTAssertEqual(store.summaries.first?.title, "Lecture Notes")
        XCTAssertEqual(store.summaries.first?.pageCount, 2)
        let doc = try store.load(id)
        XCTAssertNotNil(doc.pages.first?.background.pdf)
    }

    func testRejectsNonPDF() {
        let url = dir.appendingPathComponent("fake.pdf")
        try? Data("not a pdf".utf8).write(to: url)
        XCTAssertThrowsError(try PDFImporter.pages(from: url, into: dir.appendingPathComponent("assets")))
    }
}
