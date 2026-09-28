import CoreGraphics
import XCTest
@testable import InkPad

final class LibraryTests: XCTestCase {
    private var root: URL!
    private var store: DocumentStore!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = DocumentStore(rootURL: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeDocument(in folder: UUID?) throws -> UUID {
        try store.create(title: "Doc", pageSize: PaperSize.letter.size(for: .portrait), background: PageBackground(), folderID: folder)
    }

    func testNestedFoldersAndMoving() throws {
        let math = store.createFolder(name: "Math", in: nil)
        let calc = store.createFolder(name: "Calculus", in: math.id)
        let doc = try makeDocument(in: calc.id)

        XCTAssertEqual(store.subfolders(of: nil).map(\.id), [math.id])
        XCTAssertEqual(store.subfolders(of: math.id).map(\.id), [calc.id])
        XCTAssertEqual(store.documents(in: calc.id).map(\.id), [doc])
        XCTAssertEqual(store.path(to: calc.id).map(\.name), ["Math", "Calculus"])

        store.moveDocument(doc, to: nil)
        XCTAssertEqual(store.documents(in: nil).map(\.id), [doc])
        XCTAssertTrue(store.documents(in: calc.id).isEmpty)
    }

    func testFolderCannotMoveIntoItsOwnSubfolder() {
        let a = store.createFolder(name: "A", in: nil)
        let b = store.createFolder(name: "B", in: a.id)
        store.moveFolder(a.id, to: b.id)
        XCTAssertNil(store.folder(a.id)?.parentID)
        store.moveFolder(a.id, to: a.id)
        XCTAssertNil(store.folder(a.id)?.parentID)
    }

    func testDeletingFolderDeletesContents() throws {
        let a = store.createFolder(name: "A", in: nil)
        let b = store.createFolder(name: "B", in: a.id)
        let inside = try makeDocument(in: b.id)
        let outside = try makeDocument(in: nil)
        XCTAssertEqual(store.totalDocumentCount(in: a.id), 1)

        store.deleteFolder(a.id)
        XCTAssertTrue(store.folders.isEmpty)
        XCTAssertFalse(store.exists(inside))
        XCTAssertTrue(store.exists(outside))
    }

    func testFoldersPersistAndSurviveReload() throws {
        let a = store.createFolder(name: "Physics", in: nil)
        let doc = try makeDocument(in: a.id)
        let reopened = DocumentStore(rootURL: root)
        reopened.reload()
        XCTAssertEqual(reopened.folders.map(\.name), ["Physics"])
        XCTAssertEqual(reopened.documents(in: a.id).map(\.id), [doc])
    }

    @MainActor
    func testSavingAnOpenDocumentKeepsItsFolder() throws {
        let a = store.createFolder(name: "Notes", in: nil)
        let id = try makeDocument(in: a.id)
        let doc = try store.load(id)
        doc.title = "Renamed"
        let snapshot = try XCTUnwrap(doc.takeSnapshot())
        try DocumentStore.write(snapshot, to: store.packageURL(id))
        store.reload()
        XCTAssertEqual(store.documents(in: a.id).first?.title, "Renamed")
    }
}
