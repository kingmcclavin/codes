import CoreGraphics
import XCTest
@testable import Basis

@MainActor
final class BackupTests: XCTestCase {
    private var temp: URL!

    override func setUp() async throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: temp)
    }

    /// A library with Math › Calculus › "Limits" (ink + image) and a top-level "Ideas".
    private func makeLibrary() throws -> (DocumentStore, UUID) {
        let store = DocumentStore(rootURL: temp.appendingPathComponent("lib"))
        let math = store.createFolder(name: "Math", in: nil)
        let calculus = store.createFolder(name: "Calculus", in: math.id)
        let id = try store.create(title: "Limits", pageSize: CGSize(width: 600, height: 800), background: PageBackground(), folderID: calculus.id)
        _ = try store.create(title: "Ideas", pageSize: CGSize(width: 600, height: 800), background: PageBackground())

        // Give "Limits" some ink and an image.
        let pkg = store.packageURL(id)
        var page = PageData(size: CGSize(width: 600, height: 800), background: PageBackground(template: .grid))
        page.elements = [
            .stroke(Stroke(points: [InkPoint(location: CGPoint(x: 10, y: 10)), InkPoint(location: CGPoint(x: 90, y: 40))],
                           style: PenPreset.ballpoint.style)),
            .image(ImageElement(assetName: "photo.png", box: BoxGeometry(rect: CGRect(x: 100, y: 100, width: 50, height: 50)))),
        ]
        var manifest = try DocumentStore.decoder().decode(DocumentManifest.self, from: Data(contentsOf: DocumentStore.manifestURL(pkg)))
        manifest.pageIDs = [page.id]
        try DocumentStore.write(DocumentModel.Snapshot(manifest: manifest, dirtyPages: [page], livePageIDs: [page.id]), to: pkg)
        try Data("PNGDATA".utf8).write(to: DocumentStore.assetsURL(pkg).appendingPathComponent("photo.png"))
        store.reload()
        return (store, id)
    }

    func testEditableBackupMirrorsFoldersAndRestoresEverything() throws {
        let (store, id) = try makeLibrary()
        let (backup, report) = try BackupManager.createBackup(BackupManager.snapshot(of: store), format: .editable,
                                                              calculatorData: nil, in: temp)
        XCTAssertEqual(report.notebooks, 2)
        XCTAssertEqual(report.folders, 2)
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: backup.appendingPathComponent("Math/Calculus/Limits.basis").path))
        XCTAssertTrue(fm.fileExists(atPath: backup.appendingPathComponent("Ideas.basis").path))

        // Restore into an empty library.
        let fresh = DocumentStore(rootURL: temp.appendingPathComponent("fresh"))
        let restored = BackupManager.restore(from: [backup], into: fresh, calculator: nil)
        XCTAssertEqual(restored.notebooks, 2)
        XCTAssertEqual(fresh.subfolders(of: nil).map(\.name), ["Math"])
        let math = try XCTUnwrap(fresh.subfolders(of: nil).first)
        let calculus = try XCTUnwrap(fresh.subfolders(of: math.id).first)
        XCTAssertEqual(calculus.name, "Calculus")
        XCTAssertEqual(fresh.documents(in: calculus.id).map(\.id), [id])

        // The notebook is fully editable: same strokes, same image.
        let doc = try fresh.load(id)
        XCTAssertEqual(doc.pages.count, 1)
        XCTAssertEqual(doc.pages[0].allElements.filter(\.isStroke).count, 1)
        XCTAssertEqual(doc.pages[0].background.template, .grid)
        let image = DocumentStore.assetsURL(fresh.packageURL(id)).appendingPathComponent("photo.png")
        XCTAssertEqual(try Data(contentsOf: image), Data("PNGDATA".utf8))

        // Restoring again doesn't duplicate anything.
        let again = BackupManager.restore(from: [backup], into: fresh, calculator: nil)
        XCTAssertEqual(again.notebooks, 0)
        XCTAssertEqual(again.skipped, 2)
        XCTAssertEqual(fresh.summaries.count, 2)
        XCTAssertEqual(fresh.folders.count, 2)
    }

    func testSingleFileRestoreAndCalculatorData() throws {
        let (store, _) = try makeLibrary()
        let calcData = try JSONEncoder().encode(["variables": [CalcVariable(name: "g", expression: "9.81")]])
        let (backup, _) = try BackupManager.createBackup(BackupManager.snapshot(of: store), format: .editable,
                                                         calculatorData: calcData, in: temp)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.appendingPathComponent(BackupManager.calculatorFileName).path))

        let fresh = DocumentStore(rootURL: temp.appendingPathComponent("single"))
        let calc = CalculatorStore(directory: temp.appendingPathComponent("calc"))
        let report = BackupManager.restore(from: [backup.appendingPathComponent("Ideas.basis"),
                                                 backup.appendingPathComponent(BackupManager.calculatorFileName)],
                                           into: fresh, calculator: calc)
        XCTAssertEqual(report.notebooks, 1)
        XCTAssertEqual(fresh.summaries.map(\.title), ["Ideas"])
        XCTAssertTrue(fresh.folders.isEmpty)
        XCTAssertEqual(calc.variables.map(\.name), ["g"])
    }

    func testPDFBackup() throws {
        let (store, _) = try makeLibrary()
        let (backup, report) = try BackupManager.createBackup(BackupManager.snapshot(of: store), format: .pdf,
                                                              calculatorData: nil, in: temp)
        XCTAssertEqual(report.notebooks, 2)
        let pdf = try Data(contentsOf: backup.appendingPathComponent("Math/Calculus/Limits.pdf"))
        XCTAssertEqual(String(decoding: pdf.prefix(4), as: UTF8.self), "%PDF")
    }

    func testFileNames() {
        XCTAssertEqual(BackupManager.safeName("Physics: Ch. 1/2"), "Physics- Ch. 1-2")
        XCTAssertEqual(BackupManager.safeName("  .hidden"), "hidden")
        XCTAssertEqual(BackupManager.safeName(""), "Untitled")
        let dir = temp.appendingPathComponent("names")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let first = BackupManager.uniqueURL(in: dir, name: "Notes", ext: "basis")
        FileManager.default.createFile(atPath: first.path, contents: Data())
        XCTAssertEqual(BackupManager.uniqueURL(in: dir, name: "Notes", ext: "basis").lastPathComponent, "Notes 2.basis")
    }
}
