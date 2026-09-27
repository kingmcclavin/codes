import Foundation
import UIKit

struct DocumentSummary: Identifiable, Hashable {
    var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var pageCount: Int
    var pageSize: CGSize

    static func == (a: DocumentSummary, b: DocumentSummary) -> Bool {
        a.id == b.id && a.title == b.title && a.modifiedAt == b.modifiedAt && a.pageCount == b.pageCount
    }

    func hash(into h: inout Hasher) { h.combine(id) }
}

enum DocumentStoreError: LocalizedError {
    case missingManifest
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .missingManifest: return "The document could not be found."
        case let .unsupportedVersion(v): return "This document was created by a newer version of InkPad (format \(v))."
        }
    }
}

/// On-disk layout (inside the app's Documents folder, visible in Files):
/// ```
/// InkPad Documents/
///   <uuid>.inkpad/
///     manifest.json        title, page order, tool settings, view state
///     pages/<uuid>.json    one file per page (only dirty pages are rewritten)
///     assets/<name>        inserted images
/// ```
final class DocumentStore: ObservableObject, @unchecked Sendable {
    static let shared = DocumentStore()

    let rootURL: URL
    @Published private(set) var summaries: [DocumentSummary] = []

    init(rootURL: URL? = nil) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.rootURL = rootURL ?? docs.appendingPathComponent("InkPad Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
    }

    // MARK: Paths

    func packageURL(_ id: UUID) -> URL {
        rootURL.appendingPathComponent("\(id.uuidString).inkpad", isDirectory: true)
    }

    static func manifestURL(_ pkg: URL) -> URL { pkg.appendingPathComponent("manifest.json") }
    static func pagesURL(_ pkg: URL) -> URL { pkg.appendingPathComponent("pages", isDirectory: true) }
    static func assetsURL(_ pkg: URL) -> URL { pkg.appendingPathComponent("assets", isDirectory: true) }
    static func pageURL(_ pkg: URL, _ id: UUID) -> URL { pagesURL(pkg).appendingPathComponent("\(id.uuidString).json") }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: Library

    func reload() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)) ?? []
        var result: [DocumentSummary] = []
        for url in urls where url.pathExtension == "inkpad" {
            guard let data = try? Data(contentsOf: Self.manifestURL(url)),
                  let m = try? Self.decoder().decode(DocumentManifest.self, from: data) else { continue }
            result.append(DocumentSummary(id: m.id, title: m.title, createdAt: m.createdAt, modifiedAt: m.modifiedAt,
                                          pageCount: m.pageIDs.count, pageSize: m.firstPageSize))
        }
        summaries = result.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func exists(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: Self.manifestURL(packageURL(id)).path)
    }

    @discardableResult
    func create(title: String, pageSize: CGSize, background: PageBackground, settings: ToolSettings = ToolSettings()) throws -> UUID {
        let id = UUID()
        let page = PageData(size: pageSize, background: background)
        let now = Date()
        let manifest = DocumentManifest(id: id, title: title, createdAt: now, modifiedAt: now, pageIDs: [page.id],
                                        firstPageSize: pageSize, toolSettings: settings, viewState: ViewState())
        try Self.write(DocumentModel.Snapshot(manifest: manifest, dirtyPages: [page], livePageIDs: [page.id]),
                       to: packageURL(id))
        reload()
        return id
    }

    /// Loads a document. Safe to call off the main thread.
    func load(_ id: UUID) throws -> DocumentModel {
        let pkg = packageURL(id)
        guard let data = try? Data(contentsOf: Self.manifestURL(pkg)) else { throw DocumentStoreError.missingManifest }
        let m = try Self.decoder().decode(DocumentManifest.self, from: data)
        guard m.formatVersion <= DocumentManifest.currentFormatVersion else { throw DocumentStoreError.unsupportedVersion(m.formatVersion) }
        let decoder = Self.decoder()
        var pages: [PageData] = []
        for pid in m.pageIDs {
            if let pdata = try? Data(contentsOf: Self.pageURL(pkg, pid)),
               let page = try? decoder.decode(PageData.self, from: pdata) {
                pages.append(page)
            } else {
                // Never lose the page order because one file is unreadable.
                pages.append(PageData(id: pid, size: m.firstPageSize, background: PageBackground()))
            }
        }
        if pages.isEmpty { pages = [PageData(size: PaperSize.letter.size(for: .portrait), background: PageBackground())] }
        Self.removeUnreferencedAssets(pkg: pkg, pages: pages)
        return DocumentModel(id: m.id, title: m.title, createdAt: m.createdAt, modifiedAt: m.modifiedAt, pages: pages,
                             toolSettings: m.toolSettings, viewState: m.viewState, assetsURL: Self.assetsURL(pkg))
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: packageURL(id))
        reload()
    }

    func rename(_ id: UUID, to title: String) {
        let url = Self.manifestURL(packageURL(id))
        guard let data = try? Data(contentsOf: url), var m = try? Self.decoder().decode(DocumentManifest.self, from: data) else { return }
        m.title = title
        m.modifiedAt = Date()
        if let out = try? Self.encoder().encode(m) { try? out.write(to: url, options: .atomic) }
        reload()
    }

    func duplicate(_ id: UUID) {
        let src = packageURL(id)
        let newID = UUID()
        let dst = packageURL(newID)
        do {
            try FileManager.default.copyItem(at: src, to: dst)
            let url = Self.manifestURL(dst)
            var m = try Self.decoder().decode(DocumentManifest.self, from: Data(contentsOf: url))
            m.id = newID
            m.title += " Copy"
            m.createdAt = Date()
            m.modifiedAt = Date()
            try Self.encoder().encode(m).write(to: url, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: dst)
        }
        reload()
    }

    // MARK: Writing (background safe)

    static func write(_ snapshot: DocumentModel.Snapshot, to pkg: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: pagesURL(pkg), withIntermediateDirectories: true)
        try fm.createDirectory(at: assetsURL(pkg), withIntermediateDirectories: true)
        let enc = encoder()
        for page in snapshot.dirtyPages where snapshot.livePageIDs.contains(page.id) {
            try enc.encode(page).write(to: pageURL(pkg, page.id), options: .atomic)
        }
        // Manifest last: it is the commit point that references the pages.
        try enc.encode(snapshot.manifest).write(to: manifestURL(pkg), options: .atomic)

        // Remove files of deleted pages.
        if let files = try? fm.contentsOfDirectory(at: pagesURL(pkg), includingPropertiesForKeys: nil) {
            let live = Set(snapshot.manifest.pageIDs.map { "\($0.uuidString).json" })
            for f in files where !live.contains(f.lastPathComponent) { try? fm.removeItem(at: f) }
        }
    }

    /// Deletes image files no page refers to (only on open, when there is no undo history).
    private static func removeUnreferencedAssets(pkg: URL, pages: [PageData]) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: assetsURL(pkg), includingPropertiesForKeys: nil) else { return }
        var used = Set<String>()
        for p in pages {
            for case let .image(img) in p.elements { used.insert(img.assetName) }
        }
        for f in files where !used.contains(f.lastPathComponent) { try? fm.removeItem(at: f) }
    }
}
