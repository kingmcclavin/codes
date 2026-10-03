import CoreGraphics
import Foundation

enum DocumentChange {
    /// Element content changed inside `dirtyRect` (page coordinates).
    case elements(pageID: UUID, dirtyRect: CGRect)
    /// Page size or background changed.
    case pageSettings(pageID: UUID)
    /// Pages were added, removed or reordered.
    case pageStructure
    /// An endless page got bigger; only the new area needs drawing.
    case pageGrew(pageID: UUID, oldSize: CGSize)
    /// Title or other metadata.
    case metadata
}

@MainActor
protocol DocumentObserver: AnyObject {
    func document(_ document: DocumentModel, didChange change: DocumentChange)
}

/// The in-memory document. All mutations go through the primitive methods
/// below (normally invoked by `EditCommand`s), which keep observers and
/// autosave informed. Main thread only.
@MainActor
final class DocumentModel {
    let id: UUID
    let createdAt: Date
    /// Folder holding image assets for this document.
    let assetsURL: URL
    /// Library folder (documents are only moved while closed).
    let folderID: UUID?

    private(set) var pages: [PageStore]
    var title: String { didSet { manifestDirty = true; notify(.metadata) } }
    var toolSettings: ToolSettings { didSet { if toolSettings != oldValue { manifestDirty = true; changeCount += 1 } } }
    var viewState: ViewState { didSet { if viewState != oldValue { manifestDirty = true; changeCount += 1 } } }
    private(set) var modifiedAt: Date

    /// Save bookkeeping.
    private(set) var dirtyPageIDs: Set<UUID> = []
    private(set) var manifestDirty = false
    private(set) var changeCount = 0 { didSet { onDirty?() } }
    var onDirty: (() -> Void)?

    private struct WeakObserver { weak var value: DocumentObserver? }
    private var observers: [WeakObserver] = []

    nonisolated init(id: UUID, title: String, createdAt: Date, modifiedAt: Date, pages: [PageData],
         toolSettings: ToolSettings, viewState: ViewState, assetsURL: URL, folderID: UUID? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.pages = pages.map(PageStore.init(data:))
        self.toolSettings = toolSettings
        self.viewState = viewState
        self.assetsURL = assetsURL
        self.folderID = folderID
    }

    // MARK: Observation

    func addObserver(_ o: DocumentObserver) {
        observers.removeAll { $0.value == nil }
        observers.append(WeakObserver(value: o))
    }

    func removeObserver(_ o: DocumentObserver) {
        observers.removeAll { $0.value == nil || $0.value === o }
    }

    private func notify(_ change: DocumentChange) {
        for o in observers { o.value?.document(self, didChange: change) }
    }

    private func touch(page id: UUID?) {
        if let id { dirtyPageIDs.insert(id) }
        modifiedAt = Date()
        manifestDirty = true
        changeCount += 1
    }

    // MARK: Lookup

    func page(_ id: UUID) -> PageStore? { pages.first { $0.id == id } }
    func pageIndex(_ id: UUID) -> Int? { pages.firstIndex { $0.id == id } }

    // MARK: Element primitives

    func insertElement(_ e: CanvasElement, at index: Int?, page pageID: UUID) {
        guard let page = page(pageID) else { return }
        page.insert(e, at: index)
        touch(page: pageID)
        notify(.elements(pageID: pageID, dirtyRect: e.bounds))
    }

    @discardableResult
    func removeElement(_ id: UUID, page pageID: UUID) -> (index: Int, element: CanvasElement)? {
        guard let page = page(pageID), let removed = page.remove(id) else { return nil }
        touch(page: pageID)
        notify(.elements(pageID: pageID, dirtyRect: removed.element.bounds))
        return removed
    }

    func replaceElement(_ e: CanvasElement, page pageID: UUID) {
        guard let page = page(pageID), let old = page.replace(e) else { return }
        touch(page: pageID)
        notify(.elements(pageID: pageID, dirtyRect: old.bounds.union(e.bounds)))
    }

    func moveElement(_ id: UUID, to index: Int, page pageID: UUID) {
        guard let page = page(pageID), let e = page.element(id) else { return }
        page.move(id, to: index)
        touch(page: pageID)
        notify(.elements(pageID: pageID, dirtyRect: e.bounds))
    }

    /// Hides elements from page rendering (e.g. while they are dragged in the overlay).
    func setHidden(_ ids: Set<UUID>, page pageID: UUID) {
        guard let page = page(pageID) else { return }
        let before = page.hiddenIDs
        guard before != ids else { return }
        page.setHidden(ids)
        let changed = before.symmetricDifference(ids)
        let rect = changed.compactMap { page.element($0)?.bounds }.reduce(CGRect.null) { $0.union($1) }
        if !rect.isNull { notify(.elements(pageID: pageID, dirtyRect: rect)) }
    }

    // MARK: Page primitives

    func insertPage(_ data: PageData, at index: Int) {
        let store = PageStore(data: data)
        pages.insert(store, at: index.clamped(0, pages.count))
        touch(page: data.id)
        notify(.pageStructure)
    }

    @discardableResult
    func removePage(at index: Int) -> PageData? {
        guard pages.indices.contains(index) else { return nil }
        let data = pages.remove(at: index).pageData()
        dirtyPageIDs.remove(data.id)
        touch(page: nil)
        notify(.pageStructure)
        return data
    }

    func movePage(from: Int, to: Int) {
        guard pages.indices.contains(from) else { return }
        let p = pages.remove(at: from)
        pages.insert(p, at: to.clamped(0, pages.count))
        touch(page: nil)
        notify(.pageStructure)
    }

    /// Enlarges a page (endless pages) without redrawing what's already there.
    func growPage(_ pageID: UUID, to size: CGSize) {
        guard let page = page(pageID), size != page.size else { return }
        let old = page.size
        page.size = size
        touch(page: pageID)
        notify(.pageGrew(pageID: pageID, oldSize: old))
    }

    func setPageSettings(_ pageID: UUID, size: CGSize, background: PageBackground) {
        guard let page = page(pageID) else { return }
        let sizeChanged = page.size != size
        page.size = size
        page.background = background
        touch(page: pageID)
        notify(sizeChanged ? .pageStructure : .pageSettings(pageID: pageID))
    }

    // MARK: Saving

    struct Snapshot {
        var manifest: DocumentManifest
        var dirtyPages: [PageData]
        var livePageIDs: Set<UUID>
    }

    /// Captures everything that needs writing and clears the dirty flags.
    /// Page data are value types, so encoding can safely happen off the main thread.
    func takeSnapshot(forceAllPages: Bool = false) -> Snapshot? {
        guard forceAllPages || manifestDirty || !dirtyPageIDs.isEmpty else { return nil }
        let manifest = DocumentManifest(
            id: id, title: title, createdAt: createdAt, modifiedAt: modifiedAt,
            pageIDs: pages.map(\.id), firstPageSize: pages.first?.size ?? .zero,
            toolSettings: toolSettings, viewState: viewState, folderID: folderID)
        let dirty = pages.filter { forceAllPages || dirtyPageIDs.contains($0.id) }.map { $0.pageData() }
        dirtyPageIDs.removeAll()
        manifestDirty = false
        return Snapshot(manifest: manifest, dirtyPages: dirty, livePageIDs: Set(pages.map(\.id)))
    }

    /// Called when a background save failed so the data is written next time.
    func restoreDirty(_ snapshot: Snapshot) {
        manifestDirty = true
        for p in snapshot.dirtyPages where snapshot.livePageIDs.contains(p.id) { dirtyPageIDs.insert(p.id) }
        changeCount += 1
    }
}
