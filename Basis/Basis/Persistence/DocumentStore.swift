import Foundation
import UIKit

struct DocumentSummary: Identifiable, Hashable {
    var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var pageCount: Int
    var pageSize: CGSize
    var folderID: UUID?
    var color: RGBAColor?
    var icon: String?

    static func == (a: DocumentSummary, b: DocumentSummary) -> Bool {
        a.id == b.id && a.title == b.title && a.modifiedAt == b.modifiedAt && a.pageCount == b.pageCount
            && a.folderID == b.folderID && a.color == b.color && a.icon == b.icon
    }

    func hash(into h: inout Hasher) { h.combine(id) }
}

/// A library folder. Folders can contain documents and other folders.
struct Folder: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// Containing folder (nil = top level).
    var parentID: UUID?
    var createdAt = Date()
    /// Custom color and SF Symbol shown in the library (nil = default).
    var color: RGBAColor?
    var icon: String?
}

enum DocumentStoreError: LocalizedError {
    case missingManifest
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .missingManifest: return "The document could not be found."
        case let .unsupportedVersion(v): return "This document was created by a newer version of Basis (format \(v))."
        }
    }
}

/// On-disk layout (inside the app's Documents folder, visible in Files):
/// ```
/// Basis Documents/
///   folders.json         library folder tree (documents reference their folder
///                        by id in their manifest)
///   <uuid>.basis/
///     manifest.json        title, page order, tool settings, view state
///     pages/<uuid>.json    one file per page (only dirty pages are rewritten)
///     assets/<name>        inserted images
/// ```
final class DocumentStore: ObservableObject, @unchecked Sendable {
    static let shared = DocumentStore()

    let rootURL: URL
    @Published private(set) var summaries: [DocumentSummary] = []
    @Published private(set) var folders: [Folder] = []

    init(rootURL: URL? = nil) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = rootURL ?? docs.appendingPathComponent("Basis Documents", isDirectory: true)
        self.rootURL = root
        if rootURL == nil {
            Self.migrateLegacyFolder(docs.appendingPathComponent("InkPad Documents", isDirectory: true), to: root)
        }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        Self.migrateLegacyPackages(in: root)
    }

    static let packageExtension = "basis"
    private static let legacyPackageExtension = "inkpad"

    /// The app used to be called InkPad: move its "InkPad Documents" folder to
    /// "Basis Documents" (merging if both exist).
    static func migrateLegacyFolder(_ legacy: URL, to root: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacy.path) else { return }
        if !fm.fileExists(atPath: root.path) {
            try? fm.moveItem(at: legacy, to: root)
            return
        }
        for item in (try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)) ?? [] {
            let target = root.appendingPathComponent(item.lastPathComponent)
            if !fm.fileExists(atPath: target.path) { try? fm.moveItem(at: item, to: target) }
        }
        if ((try? fm.contentsOfDirectory(atPath: legacy.path)) ?? []).isEmpty { try? fm.removeItem(at: legacy) }
    }

    /// Renames notebook packages from `<id>.inkpad` to `<id>.basis`.
    static func migrateLegacyPackages(in root: URL) {
        let fm = FileManager.default
        for url in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        where url.pathExtension == legacyPackageExtension {
            let target = url.deletingPathExtension().appendingPathExtension(packageExtension)
            if !fm.fileExists(atPath: target.path) { try? fm.moveItem(at: url, to: target) }
        }
    }

    // MARK: Paths

    func packageURL(_ id: UUID) -> URL {
        rootURL.appendingPathComponent("\(id.uuidString).\(Self.packageExtension)", isDirectory: true)
    }

    static func manifestURL(_ pkg: URL) -> URL { pkg.appendingPathComponent("manifest.json") }
    static func pagesURL(_ pkg: URL) -> URL { pkg.appendingPathComponent("pages", isDirectory: true) }
    static func assetsURL(_ pkg: URL) -> URL { pkg.appendingPathComponent("assets", isDirectory: true) }
    static func pageURL(_ pkg: URL, _ id: UUID) -> URL { pagesURL(pkg).appendingPathComponent("\(id.uuidString).json") }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private var foldersURL: URL { rootURL.appendingPathComponent("folders.json") }

    // MARK: Library

    func reload() {
        if let data = try? Data(contentsOf: foldersURL), let list = try? Self.decoder().decode([Folder].self, from: data) {
            folders = list
        }
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)) ?? []
        var result: [DocumentSummary] = []
        for url in urls where url.pathExtension == Self.packageExtension {
            guard let data = try? Data(contentsOf: Self.manifestURL(url)),
                  let m = try? Self.decoder().decode(DocumentManifest.self, from: data) else { continue }
            result.append(DocumentSummary(id: m.id, title: m.title, createdAt: m.createdAt, modifiedAt: m.modifiedAt,
                                          pageCount: m.pageIDs.count, pageSize: m.firstPageSize,
                                          folderID: m.folderID.flatMap { id in folders.contains { $0.id == id } ? id : nil },
                                          color: m.color, icon: m.icon))
        }
        summaries = result.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: Search

    struct SearchablePage: Sendable {
        var documentID: UUID
        var title: String
        var pageIndex: Int
        var section: String?
        /// Typed text and calculation cards on the page.
        var text: String
    }

    /// Reads the text of every page from disk (safe off the main thread).
    /// Handwriting isn't searchable – only typed text and calculations.
    func searchablePages() -> [SearchablePage] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)) ?? []
        var result: [SearchablePage] = []
        let decoder = Self.decoder()
        for pkg in urls where pkg.pathExtension == Self.packageExtension {
            guard let data = try? Data(contentsOf: Self.manifestURL(pkg)),
                  let m = try? decoder.decode(DocumentManifest.self, from: data) else { continue }
            var section: String?
            for (i, pid) in m.pageIDs.enumerated() {
                guard let pageData = try? Data(contentsOf: Self.pageURL(pkg, pid)),
                      let page = try? decoder.decode(PageData.self, from: pageData) else { continue }
                if let s = page.background.section, !s.isEmpty { section = s }
                let texts = page.elements.compactMap { e -> String? in
                    if case let .text(t) = e { return t.text }
                    return nil
                }
                let pageText = ([page.background.section].compactMap { $0 } + texts).joined(separator: "\n")
                if !pageText.isEmpty {
                    result.append(SearchablePage(documentID: m.id, title: m.title, pageIndex: i, section: section, text: pageText))
                }
            }
        }
        return result
    }

    func exists(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: Self.manifestURL(packageURL(id)).path)
    }

    @discardableResult
    func create(title: String, pageSize: CGSize, background: PageBackground, settings: ToolSettings = ToolSettings(),
                folderID: UUID? = nil) throws -> UUID {
        let id = UUID()
        let page = PageData(size: pageSize, background: background)
        let now = Date()
        let manifest = DocumentManifest(id: id, title: title, createdAt: now, modifiedAt: now, pageIDs: [page.id],
                                        firstPageSize: pageSize, toolSettings: settings, viewState: ViewState(),
                                        folderID: folderID)
        try Self.write(DocumentModel.Snapshot(manifest: manifest, dirtyPages: [page], livePageIDs: [page.id]),
                       to: packageURL(id))
        reload()
        return id
    }

    /// Creates a notebook whose pages are the pages of a PDF.
    @discardableResult
    func createFromPDF(_ url: URL, folderID: UUID? = nil) throws -> UUID {
        let id = UUID()
        let pkg = packageURL(id)
        do {
            let pages = try PDFImporter.pages(from: url, into: Self.assetsURL(pkg))
            let now = Date()
            let manifest = DocumentManifest(id: id, title: PDFImporter.title(for: url), createdAt: now, modifiedAt: now,
                                            pageIDs: pages.map(\.id), firstPageSize: pages[0].size,
                                            toolSettings: ToolSettings(), viewState: ViewState(), folderID: folderID)
            try Self.write(DocumentModel.Snapshot(manifest: manifest, dirtyPages: pages, livePageIDs: Set(pages.map(\.id))),
                           to: pkg)
        } catch {
            try? FileManager.default.removeItem(at: pkg)
            throw error
        }
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
                             toolSettings: m.toolSettings, viewState: m.viewState, assetsURL: Self.assetsURL(pkg),
                             folderID: m.folderID)
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: packageURL(id))
        reload()
    }

    func rename(_ id: UUID, to title: String) {
        updateManifest(id) {
            $0.title = title
            $0.modifiedAt = Date()
        }
        reload()
    }

    private func updateManifest(_ id: UUID, _ change: (inout DocumentManifest) -> Void) {
        let url = Self.manifestURL(packageURL(id))
        guard let data = try? Data(contentsOf: url), var m = try? Self.decoder().decode(DocumentManifest.self, from: data) else { return }
        change(&m)
        if let out = try? Self.encoder().encode(m) { try? out.write(to: url, options: .atomic) }
    }

    // MARK: Folders

    func folder(_ id: UUID?) -> Folder? {
        guard let id else { return nil }
        return folders.first { $0.id == id }
    }

    func subfolders(of parent: UUID?) -> [Folder] {
        folders.filter { $0.parentID == parent }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func documents(in folder: UUID?) -> [DocumentSummary] {
        summaries.filter { $0.folderID == folder }
    }

    /// Folder chain from the top level down to `id` (inclusive).
    func path(to id: UUID?) -> [Folder] {
        var chain: [Folder] = []
        var current = folder(id)
        while let f = current, !chain.contains(where: { $0.id == f.id }) {
            chain.insert(f, at: 0)
            current = folder(f.parentID)
        }
        return chain
    }

    /// `id` plus every folder nested inside it.
    func descendants(of id: UUID) -> Set<UUID> {
        var result: Set<UUID> = [id]
        var queue = [id]
        while let next = queue.popLast() {
            for f in folders where f.parentID == next && !result.contains(f.id) {
                result.insert(f.id)
                queue.append(f.id)
            }
        }
        return result
    }

    /// Number of documents and folders directly inside a folder.
    func itemCount(in id: UUID) -> Int {
        folders.filter { $0.parentID == id }.count + summaries.filter { $0.folderID == id }.count
    }

    @discardableResult
    func createFolder(name: String, in parent: UUID?) -> Folder {
        let f = Folder(name: name.isEmpty ? "New Folder" : name, parentID: parent)
        folders.append(f)
        saveFolders()
        return f
    }

    func renameFolder(_ id: UUID, to name: String) {
        guard let i = folders.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        folders[i].name = name
        saveFolders()
    }

    /// Moves a folder into another folder (nil = top level). Moving a folder
    /// into itself or one of its own subfolders is ignored.
    func moveFolder(_ id: UUID, to parent: UUID?) {
        if let parent, descendants(of: id).contains(parent) { return }
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].parentID = parent
        saveFolders()
    }

    /// Sets the library color and icon of a document or folder.
    func setAppearance(_ item: LibraryItem, color: RGBAColor?, icon: String?) {
        switch item {
        case let .document(id):
            updateManifest(id) {
                $0.color = color
                $0.icon = icon
            }
            reload()
        case let .folder(id):
            guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
            folders[i].color = color
            folders[i].icon = icon
            saveFolders()
        }
    }

    func appearance(of item: LibraryItem) -> (color: RGBAColor?, icon: String?) {
        switch item {
        case let .document(id):
            let s = summaries.first { $0.id == id }
            return (s?.color, s?.icon)
        case let .folder(id):
            let f = folder(id)
            return (f?.color, f?.icon)
        }
    }

    func moveDocument(_ id: UUID, to folder: UUID?) {
        updateManifest(id) { $0.folderID = folder }
        reload()
    }

    /// Deletes a folder together with all documents and folders inside it.
    func deleteFolder(_ id: UUID) {
        let doomed = descendants(of: id)
        for doc in summaries where doc.folderID.map(doomed.contains) ?? false {
            try? FileManager.default.removeItem(at: packageURL(doc.id))
        }
        folders.removeAll { doomed.contains($0.id) }
        saveFolders()
        reload()
    }

    /// Number of documents inside a folder, including nested folders.
    func totalDocumentCount(in id: UUID) -> Int {
        let all = descendants(of: id)
        return summaries.filter { $0.folderID.map(all.contains) ?? false }.count
    }

    private func saveFolders() {
        if let data = try? Self.encoder().encode(folders) { try? data.write(to: foldersURL, options: .atomic) }
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
        var manifest = snapshot.manifest
        if let data = try? Data(contentsOf: manifestURL(pkg)),
           let existing = try? decoder().decode(DocumentManifest.self, from: data) {
            // Folder, color and icon are owned by the library, which may change
            // them while the document is open; never overwrite them from a
            // document snapshot.
            manifest.folderID = existing.folderID
            manifest.color = existing.color
            manifest.icon = existing.icon
        }
        for page in snapshot.dirtyPages where snapshot.livePageIDs.contains(page.id) {
            try enc.encode(page).write(to: pageURL(pkg, page.id), options: .atomic)
        }
        // Manifest last: it is the commit point that references the pages.
        try enc.encode(manifest).write(to: manifestURL(pkg), options: .atomic)

        // Remove files of deleted pages.
        if let files = try? fm.contentsOfDirectory(at: pagesURL(pkg), includingPropertiesForKeys: nil) {
            let live = Set(manifest.pageIDs.map { "\($0.uuidString).json" })
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
            if let pdf = p.background.pdf { used.insert(pdf.assetName) }
        }
        for f in files where !used.contains(f.lastPathComponent) { try? fm.removeItem(at: f) }
    }
}
