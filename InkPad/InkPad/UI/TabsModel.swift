import SwiftUI

/// Browser-style tabs of open documents.
///
/// Open documents stay loaded (up to `maxLoaded`) so switching tabs is
/// instant and each tab keeps its own undo history. The tab set is saved and
/// restored on launch, so the app reopens exactly as it was left.
@MainActor
final class TabsModel: ObservableObject {
    @Published private(set) var tabs: [UUID] = []
    /// Active document, or nil when the library is showing.
    @Published private(set) var activeID: UUID?
    @Published private(set) var editors: [UUID: EditorModel] = [:]
    @Published private(set) var loadErrors: [UUID: String] = [:]

    private let store: DocumentStore
    private var recentlyUsed: [UUID] = []
    private var loading: Set<UUID> = []
    private let maxLoaded = 6

    private enum Keys {
        static let tabs = "openTabs"
        static let active = "activeTab"
    }

    init(store: DocumentStore = .shared) {
        self.store = store
    }

    var showsLibrary: Bool { activeID == nil }

    func title(for id: UUID) -> String {
        if let e = editors[id] { return e.title.isEmpty ? "Untitled" : e.title }
        let t = store.summaries.first { $0.id == id }?.title ?? ""
        return t.isEmpty ? "Untitled" : t
    }

    // MARK: Tabs

    /// Opens a document in a tab (reusing an existing tab) and shows it.
    func open(_ id: UUID) {
        if !tabs.contains(id) {
            if let active = activeID, let i = tabs.firstIndex(of: active) {
                tabs.insert(id, at: i + 1)
            } else {
                tabs.append(id)
            }
        }
        activate(id)
    }

    /// Shows a tab, or the library when `id` is nil.
    func activate(_ id: UUID?) {
        if let current = activeID, current != id { editors[current]?.flush() }
        activeID = id
        if let id {
            recentlyUsed.removeAll { $0 == id }
            recentlyUsed.append(id)
            load(id)
        }
        persist()
    }

    func showLibrary() { activate(nil) }

    func close(_ id: UUID) {
        guard let index = tabs.firstIndex(of: id) else { return }
        editors[id]?.flush()
        editors[id] = nil
        loadErrors[id] = nil
        recentlyUsed.removeAll { $0 == id }
        tabs.remove(at: index)
        if activeID == id {
            // Like a browser: move to the neighbouring tab, or the library.
            let next = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)]
            activeID = nil
            activate(next)
        } else {
            persist()
        }
    }

    func closeOthers(_ id: UUID) {
        for other in tabs where other != id { close(other) }
    }

    func move(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// Closes tabs whose documents were deleted.
    func prune(existing: Set<UUID>) {
        for id in tabs where !existing.contains(id) { close(id) }
    }

    /// Saves every open document (app backgrounding).
    func flushAll() {
        for e in editors.values { e.flush() }
    }

    // MARK: Loading

    private func load(_ id: UUID) {
        guard editors[id] == nil, !loading.contains(id) else { return }
        loading.insert(id)
        loadErrors[id] = nil
        let store = self.store
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<DocumentModel, Error> in
                Result { try store.load(id) }
            }.value
            loading.remove(id)
            guard tabs.contains(id) else { return }
            switch result {
            case let .success(doc):
                editors[id] = EditorModel(document: doc, store: store)
                evictIfNeeded()
            case let .failure(error):
                loadErrors[id] = error.localizedDescription
            }
        }
    }

    /// Unloads the least recently used background tabs (they reload on demand).
    private func evictIfNeeded() {
        while editors.count > maxLoaded,
              let victim = recentlyUsed.first(where: { $0 != activeID && editors[$0] != nil }) {
            editors[victim]?.flush()
            editors[victim] = nil
            recentlyUsed.removeAll { $0 == victim }
        }
    }

    // MARK: Persistence

    private func persist() {
        UserDefaults.standard.set(tabs.map(\.uuidString), forKey: Keys.tabs)
        UserDefaults.standard.set(activeID?.uuidString, forKey: Keys.active)
    }

    /// Restores the tabs from the last session (skipping deleted documents).
    func restore() {
        let saved = (UserDefaults.standard.stringArray(forKey: Keys.tabs) ?? []).compactMap(UUID.init(uuidString:))
        tabs = saved.filter { store.exists($0) }
        // Migrate from the single "last opened document" of earlier versions.
        if tabs.isEmpty, let last = UserDefaults.standard.string(forKey: "lastOpenedDocument").flatMap(UUID.init(uuidString:)),
           store.exists(last) {
            tabs = [last]
            UserDefaults.standard.set(last.uuidString, forKey: Keys.active)
        }
        let active = UserDefaults.standard.string(forKey: Keys.active).flatMap(UUID.init(uuidString:))
        activate(active.flatMap { tabs.contains($0) ? $0 : nil })
    }
}
