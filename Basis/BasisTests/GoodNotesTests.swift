import CoreGraphics
import UIKit
import XCTest
@testable import Basis

/// Builds small GoodNotes-style files in memory (the real format, minus
/// everything Basis ignores) and checks they import correctly.
final class GoodNotesTests: XCTestCase {
    // MARK: Protobuf / zip builders

    private func varint(_ v: UInt64) -> [UInt8] {
        var v = v, out: [UInt8] = []
        repeat {
            var b = UInt8(v & 0x7F); v >>= 7
            if v != 0 { b |= 0x80 }
            out.append(b)
        } while v != 0
        return out
    }
    private func bytesField(_ n: Int, _ b: [UInt8]) -> [UInt8] { varint(UInt64(n << 3 | 2)) + varint(UInt64(b.count)) + b }
    private func string(_ n: Int, _ s: String) -> [UInt8] { bytesField(n, Array(s.utf8)) }
    private func number(_ n: Int, _ v: UInt64) -> [UInt8] { varint(UInt64(n << 3)) + varint(v) }
    private func float(_ n: Int, _ f: Float) -> [UInt8] {
        let bits = f.bitPattern
        return varint(UInt64(n << 3 | 5)) + [UInt8(bits & 0xFF), UInt8(bits >> 8 & 0xFF), UInt8(bits >> 16 & 0xFF), UInt8(bits >> 24)]
    }
    private func delimited(_ messages: [[UInt8]]) -> Data { Data(messages.flatMap { varint(UInt64($0.count)) + $0 }) }

    private func le32(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF)] }
    private func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }

    /// A zip with stored entries, plus deflated ones when `deflate` is set.
    private func zip(_ entries: [(String, Data)], deflate: Set<String> = []) throws -> Data {
        var out: [UInt8] = [], central: [UInt8] = []
        for (name, data) in entries {
            let compressed: [UInt8]
            var method = 0
            if deflate.contains(name), !data.isEmpty {
                compressed = [UInt8](try (data as NSData).compressed(using: .zlib) as Data)
                method = 8
            } else {
                compressed = [UInt8](data)
            }
            let offset = out.count
            let nameBytes = Array(name.utf8)
            out += le32(0x04034B50) + le16(20) + le16(0) + le16(method) + le16(0) + le16(0) + le32(0)
                + le32(compressed.count) + le32(data.count) + le16(nameBytes.count) + le16(0) + nameBytes + compressed
            central += le32(0x02014B50) + le16(20) + le16(20) + le16(0) + le16(method) + le16(0) + le16(0) + le32(0)
                + le32(compressed.count) + le32(data.count) + le16(nameBytes.count) + le16(0) + le16(0) + le16(0) + le16(0)
                + le32(0) + le32(offset) + nameBytes
        }
        let cdOffset = out.count
        out += central
        out += le32(0x06054B50) + le16(0) + le16(0) + le16(entries.count) + le16(entries.count) + le32(central.count) + le32(cdOffset) + le16(0)
        return Data(out)
    }

    /// GoodNotes stroke geometry: start point + quadratic segments, in an
    /// uncompressed "bv4-" frame.
    private func strokeBlob(width: Float, start: (Float, Float), segments: [(Float, Float, Float, Float)]) -> [UInt8] {
        func f(_ x: Float) -> [UInt8] { let b = x.bitPattern; return [UInt8(b & 0xFF), UInt8(b >> 8 & 0xFF), UInt8(b >> 16 & 0xFF), UInt8(b >> 24)] }
        var body: [UInt8] = Array("vuA(v)A(S(uu))A(S(uuuu))vA(f)".utf8) + [0]
        body += le16(2) + f(width)
        body += le32(segments.count + 1) + le16(0) + segments.flatMap { _ in le16(1) }
        body += le32(1) + f(start.0) + f(start.1)
        body += le32(segments.count) + segments.flatMap { f($0.0) + f($0.1) + f($0.2) + f($0.3) }
        body += le16(1) + le32(0)
        let tpl: [UInt8] = Array("tpl".utf8) + [0] + le32(body.count + 8) + body
        return Array("bv4-".utf8) + le32(tpl.count) + tpl + Array("bv4$".utf8)
    }

    private func stroke(_ id: String, rgba: (Float, Float, Float, Float), width: Float, erased: Bool = false) -> [[UInt8]] {
        let header = string(1, id) + bytesField(2, number(1, 2)) + (erased ? number(3, 1) : [])
        let blob = erased ? strokeBlob(width: 0, start: (0, 0), segments: []) : strokeBlob(width: width, start: (100, 100), segments: [(110, 90, 120, 100), (130, 110, 140, 100)])
        var color: [UInt8] = []
        if rgba.0 != 0 { color += float(1, rgba.0) }
        if rgba.1 != 0 { color += float(2, rgba.1) }
        if rgba.2 != 0 { color += float(3, rgba.2) }
        color += float(4, rgba.3)
        let body = bytesField(7, string(1, id) + bytesField(2, blob) + bytesField(4, color))
        return [header, body]
    }

    private let pageA = "10E2F9E8-5581-420C-8D74-4C1076A3BF2F"   // notes: …BF30
    private let pageB = "2AEA9F9C-776D-4586-9E14-0AACF2D053F4"
    private let pageGone = "429E0B79-FCCC-47D2-BDC2-446C160A189F"
    private let template = "1427F6FC-6EC3-406F-AC09-238B48489A99"
    private let paper = "DD1C07AA-190D-44EE-BD30-6615F4CC62C8"
    private let photo = "04A9B325-D138-4DA5-B6FA-DFEC4A52398F"

    private func sampleFile() throws -> Data {
        let events = delimited([
            string(1, "DOC") + bytesField(30, string(1, "DOC") + bytesField(2, string(1, "Physics Notes"))),
            string(1, template) + bytesField(2, string(2, template) + string(4, paper) + number(5, 1)
                                                 + bytesField(8, float(1, 600) + float(2, 800))),
            // Page B is first (order "4a" < "Ab"), page A second, a third page was deleted.
            string(1, pageA) + bytesField(54, string(2, pageA) + bytesField(3, string(1, template)) + bytesField(4, string(1, "Ab"))),
            string(1, pageB) + bytesField(54, string(2, pageB) + bytesField(3, string(1, template)) + bytesField(4, string(1, "4a"))),
            string(1, pageGone) + bytesField(54, string(2, pageGone) + bytesField(3, string(1, template)) + bytesField(4, string(1, "Z"))),
            string(1, pageGone) + bytesField(56, string(2, pageGone)),
        ])
        // Page B: a blue pen stroke, an erased stroke and an image.
        let notesB = delimited(
            stroke("S1", rgba: (0, 0, 1, 1), width: 2)
            + stroke("S2", rgba: (0, 0, 0, 1), width: 2, erased: true)
            + [string(1, "IMG") + bytesField(2, number(1, 3)),
               bytesField(1, string(1, "IMG") + bytesField(2, bytesField(1, float(1, 50) + float(2, 60)) + bytesField(2, float(1, 200) + float(2, 100)))
                             + string(4, photo))])
        // Page A: a highlighter and near-white ("dark mode") ink.
        let notesA = delimited(stroke("H1", rgba: (0, 0.42, 0.83, 0.5), width: 36) + stroke("W1", rgba: (0.99, 0.99, 0.99, 1), width: 1.5))
        return try zip([
            ("index.events.pb", events),
            ("notes/10E2F9E8-5581-420C-8D74-4C1076A3BF30", notesA),
            ("notes/2AEA9F9C-776D-4586-9E14-0AACF2D053F5", notesB),
            ("attachments/\(paper)", Data("%PDF-1.7 paper".utf8)),
            ("attachments/\(photo)", Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])),
        ], deflate: ["index.events.pb", "notes/2AEA9F9C-776D-4586-9E14-0AACF2D053F5"])
    }

    // MARK: Tests

    func testImportsPagesInkAndImages() throws {
        let zip = try ZipReader(data: sampleFile())
        let result = try GoodNotesImporter.convert(zip: zip, fallbackTitle: "fallback")
        let archive = result.archive
        XCTAssertEqual(archive.manifest.title, "Physics Notes")
        XCTAssertEqual(archive.pages.count, 2)                 // deleted page left out
        XCTAssertEqual(archive.pages[0].size, CGSize(width: 600, height: 800))
        XCTAssertEqual(result.strokes, 3)                       // erased stroke skipped
        XCTAssertEqual(result.images, 1)

        // First page (B): pen stroke + image, on the template's PDF paper.
        let first = archive.pages[0]
        XCTAssertEqual(first.elements.count, 2)
        guard case let .stroke(pen) = first.elements[0] else { return XCTFail("expected a stroke") }
        XCTAssertEqual(pen.style.kind, .fineliner)
        XCTAssertEqual(pen.style.color, RGBAColor(r: 0, g: 0, b: 1, a: 1))
        XCTAssertEqual(pen.style.width, 2, accuracy: 0.001)
        XCTAssertGreaterThan(pen.points.count, 4)               // curves are sampled
        XCTAssertEqual(pen.points.first?.location, CGPoint(x: 100, y: 100))
        XCTAssertEqual(pen.points.last?.location, CGPoint(x: 140, y: 100))
        guard case let .image(image) = first.elements[1] else { return XCTFail("expected an image") }
        XCTAssertEqual(image.box.boundingRect, CGRect(x: 50, y: 60, width: 200, height: 100))
        XCTAssertEqual(archive.assets[image.assetName], Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]))
        let pdf = try XCTUnwrap(first.background.pdf)
        XCTAssertEqual(pdf.pageIndex, 0)
        XCTAssertEqual(archive.assets[pdf.assetName], Data("%PDF-1.7 paper".utf8))

        // Second page (A): highlighter and white ink keep their colours.
        let second = archive.pages[1]
        guard case let .stroke(highlight) = second.elements[0], case let .stroke(ink) = second.elements[1] else {
            return XCTFail("expected two strokes")
        }
        XCTAssertTrue(highlight.style.isHighlighter)
        XCTAssertEqual(highlight.style.width, 36, accuracy: 0.001)
        XCTAssertEqual(highlight.style.opacity, 0.5, accuracy: 0.001)
        XCTAssertEqual(ink.style.color.r, 0.99, accuracy: 0.001)
        XCTAssertEqual(ink.style.color.g, 0.99, accuracy: 0.001)
    }

    /// A small dark PDF (like GoodNotes' paper templates).
    private func smallDarkPDF() -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 130)).pdfData { ctx in
            ctx.beginPage()
            UIColor(white: 0.2, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 130))
        }
    }

    func testPaperColourIsDetected() throws {
        let colour = try XCTUnwrap(GoodNotesImporter.paperColor(of: smallDarkPDF(), pageIndex: 0))
        XCTAssertEqual(colour.r, 0.2, accuracy: 0.03)
        XCTAssertFalse(colour.isLight)
        XCTAssertNil(GoodNotesImporter.paperColor(of: Data("not a pdf".utf8), pageIndex: 0))
    }

    /// A PDF smaller than the page must be scaled up to fill it, not drawn
    /// small in the middle.
    func testSmallPDFFillsTheWholePage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try smallDarkPDF().write(to: dir.appendingPathComponent("paper.pdf"))

        let size = CGSize(width: 400, height: 520)   // same shape, 4× larger
        var pixels = [UInt8](repeating: 0, count: 400 * 520 * 4)
        try pixels.withUnsafeMutableBytes { buf in
            let ctx = try XCTUnwrap(CGContext(data: buf.baseAddress, width: 400, height: 520, bitsPerComponent: 8, bytesPerRow: 1600,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            // y-down page coordinates, like the app's tiles.
            ctx.translateBy(x: 0, y: 520)
            ctx.scaleBy(x: 1, y: -1)
            var bg = PageBackground(color: .white)
            bg.pdf = PDFPageSource(assetName: "paper.pdf", pageIndex: 0)
            PageRenderer(assetsURL: dir).drawBackground(bg, pageSize: size, in: ctx, clip: CGRect(origin: .zero, size: size))
        }
        // Corners and centre are all dark paper (white would mean the PDF didn't fill the page).
        for (x, y) in [(5, 5), (394, 5), (5, 514), (394, 514), (200, 260)] {
            let i = (y * 400 + x) * 4
            XCTAssertLessThan(pixels[i], 90, "pixel \(x),\(y) is \(pixels[i])")
        }
    }

    @MainActor
    func testImportedNotebookIsEditableInTheLibrary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Physics.goodnotes")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try sampleFile().write(to: file)

        let store = DocumentStore(rootURL: root.appendingPathComponent("lib"))
        let result = try GoodNotesImporter.importFile(at: file)
        var report = BackupManager.Report()
        try BackupManager.install(result.archive, folderID: nil, store: store, report: &report)
        store.reload()
        XCTAssertEqual(store.summaries.map(\.title), ["Physics Notes"])
        let doc = try store.load(result.archive.manifest.id)
        XCTAssertEqual(doc.pages.count, 2)
        XCTAssertEqual(doc.pages[0].allElements.filter(\.isStroke).count, 1)

        // Restore also accepts .goodnotes files.
        let other = DocumentStore(rootURL: root.appendingPathComponent("other"))
        let restored = BackupManager.restore(from: [file], into: other, calculator: nil)
        XCTAssertEqual(restored.notebooks, 1)
    }

    func testRejectsOtherFiles() throws {
        XCTAssertThrowsError(try ZipReader(data: Data("not a zip".utf8)))
        let emptyZip = try ZipReader(data: zip([("hello.txt", Data("hi".utf8))]))
        XCTAssertThrowsError(try GoodNotesImporter.convert(zip: emptyZip, fallbackTitle: "x"))
    }

    func testHelpers() {
        XCTAssertEqual(GoodNotesImporter.incrementedUUID("10E2F9E8-5581-420C-8D74-4C1076A3BF2F"), "10E2F9E8-5581-420C-8D74-4C1076A3BF30")
        XCTAssertEqual(GoodNotesImporter.incrementedUUID("00000000-0000-0000-0000-0000000000FF"), "00000000-0000-0000-0000-000000000100")
        XCTAssertNil(GoodNotesImporter.incrementedUUID("nope"))
        // LZ4: "abcd" then a match of 8 bytes at offset 4 → "abcdabcdabcd".
        let block: [UInt8] = [0x44] + Array("abcd".utf8) + [4, 0]
        XCTAssertEqual(LZ4.decodeBlock(block[...], expected: 12).map { String(decoding: $0, as: UTF8.self) }, "abcdabcdabcd")
        XCTAssertNil(LZ4.decodeBlock([0x04, 0x61][...], expected: 4))   // truncated
    }
}
