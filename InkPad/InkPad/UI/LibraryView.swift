import SwiftUI

/// Navigation destinations in the library.
enum LibraryRoute: Hashable {
    /// The top level of the library.
    case library
    case folder(UUID)
    case document(UUID)
}

/// Something that can be moved to another folder.
enum LibraryItem: Identifiable, Hashable {
    case document(UUID)
    case folder(UUID)

    var id: String {
        switch self {
        case let .document(id): return "doc:\(id.uuidString)"
        case let .folder(id): return "folder:\(id.uuidString)"
        }
    }

    /// Parses the drag-and-drop payload produced by `id`.
    init?(dragPayload: String) {
        let parts = dragPayload.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let uuid = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "doc": self = .document(uuid)
        case "folder": self = .folder(uuid)
        default: return nil
        }
    }
}

/// Simple list of folders and documents – deliberately no covers or thumbnails.
struct LibraryView: View {
    /// Folder being shown (nil = top level).
    let folderID: UUID?
    let navigate: (LibraryRoute) -> Void

    @EnvironmentObject private var store: DocumentStore
    @State private var showNewDocument = false
    @State private var newFolderName = ""
    @State private var showNewFolder = false
    @State private var renaming: LibraryItem?
    @State private var renameText = ""
    @State private var moving: LibraryItem?
    @State private var deletingFolder: Folder?
    @State private var search = ""
    @State private var showExport = false

    private var folders: [Folder] {
        if search.isEmpty { return store.subfolders(of: folderID) }
        return store.folders.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var documents: [DocumentSummary] {
        if search.isEmpty { return store.documents(in: folderID) }
        // Searching looks through every folder.
        return store.summaries.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    private var title: String { store.folder(folderID)?.name ?? "Documents" }

    var body: some View {
        Group {
            if folders.isEmpty && documents.isEmpty && search.isEmpty {
                ContentUnavailableView {
                    Label(folderID == nil ? "No Documents" : "Empty Folder", systemImage: folderID == nil ? "pencil.and.scribble" : "folder")
                } description: {
                    Text("Create a document or a folder.")
                } actions: {
                    HStack {
                        Button("New Document") { showNewDocument = true }
                            .buttonStyle(.borderedProminent)
                        Button("New Folder") { startNewFolder() }
                            .buttonStyle(.bordered)
                    }
                }
                .dropDestination(for: String.self) { items, _ in drop(items, into: folderID) }
            } else {
                List {
                    if !folders.isEmpty {
                        Section("Folders") {
                            ForEach(folders) { folder in folderRow(folder) }
                        }
                    }
                    if !documents.isEmpty {
                        Section("Documents") {
                            ForEach(documents) { doc in documentRow(doc) }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .searchable(text: $search, prompt: "Search all documents")
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Document", systemImage: "doc.badge.plus") { showNewDocument = true }
                        .keyboardShortcut("n", modifiers: .command)
                    Button("New Folder", systemImage: "folder.badge.plus") { startNewFolder() }
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                } label: {
                    Label("New", systemImage: "plus")
                }
            }
            if let folder = store.folder(folderID) {
                ToolbarItem(placement: .topBarLeading) {
                    // Up one level (the sidebar shows the whole tree).
                    Button {
                        navigate(folder.parentID.map { LibraryRoute.folder($0) } ?? LibraryRoute.library)
                    } label: {
                        Label(store.folder(folder.parentID)?.name ?? "All Documents", systemImage: "chevron.left")
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
            if folderID == nil {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Export App (.ipa)…", systemImage: "app.badge") { showExport = true }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showExport) { ExportView() }
        .sheet(isPresented: $showNewDocument) {
            NewDocumentView(folderID: folderID) { id in
                showNewDocument = false
                navigate(.document(id))
            }
        }
        .sheet(item: $moving) { item in
            MoveToFolderView(item: item)
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { store.createFolder(name: newFolderName, in: folderID) }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") { commitRename() }
        }
        .confirmationDialog(deleteFolderTitle, isPresented: Binding(get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Folder", role: .destructive) {
                if let f = deletingFolder { store.deleteFolder(f.id) }
                deletingFolder = nil
            }
        } message: {
            Text("Everything inside it will be deleted. This can't be undone.")
        }
    }

    // MARK: Rows

    private func folderRow(_ folder: Folder) -> some View {
        Button { navigate(.folder(folder.id)) } label: {
            HStack(spacing: 14) {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(folder.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                    let count = store.itemCount(in: folder.id)
                    Text(search.isEmpty ? "\(count) item\(count == 1 ? "" : "s")" : locationText(folder.parentID))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .draggable(LibraryItem.folder(folder.id).id)
        .dropDestination(for: String.self) { items, _ in drop(items, into: folder.id) }
        .contextMenu {
            Button("Rename", systemImage: "pencil") { startRename(.folder(folder.id), current: folder.name) }
            Button("Move to…", systemImage: "folder") { moving = .folder(folder.id) }
            Button("Delete", systemImage: "trash", role: .destructive) { deletingFolder = folder }
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { deletingFolder = folder }
            Button("Move", systemImage: "folder") { moving = .folder(folder.id) }.tint(.indigo)
        }
    }

    private func documentRow(_ doc: DocumentSummary) -> some View {
        Button { navigate(.document(doc.id)) } label: {
            HStack(spacing: 14) {
                Image(systemName: "doc.text")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(doc.title.isEmpty ? "Untitled" : doc.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(search.isEmpty
                         ? "\(doc.pageCount) page\(doc.pageCount == 1 ? "" : "s") · \(PaperSize.describe(doc.pageSize))"
                         : locationText(doc.folderID))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(doc.modifiedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .draggable(LibraryItem.document(doc.id).id)
        .contextMenu {
            Button("Rename", systemImage: "pencil") { startRename(.document(doc.id), current: doc.title) }
            Button("Move to…", systemImage: "folder") { moving = .document(doc.id) }
            Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicate(doc.id) }
            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(doc.id) }
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(doc.id) }
            Button("Move", systemImage: "folder") { moving = .document(doc.id) }.tint(.indigo)
        }
    }

    private func locationText(_ folder: UUID?) -> String {
        let names = store.path(to: folder).map(\.name)
        return (["Documents"] + names).joined(separator: " › ")
    }

    // MARK: Actions

    private var deleteFolderTitle: String {
        guard let f = deletingFolder else { return "Delete Folder?" }
        let n = store.totalDocumentCount(in: f.id)
        return n == 0 ? "Delete “\(f.name)”?" : "Delete “\(f.name)” and \(n) document\(n == 1 ? "" : "s")?"
    }

    private func startNewFolder() {
        newFolderName = ""
        showNewFolder = true
    }

    private func startRename(_ item: LibraryItem, current: String) {
        renameText = current
        renaming = item
    }

    private func commitRename() {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        defer { renaming = nil }
        guard !name.isEmpty, let item = renaming else { return }
        switch item {
        case let .document(id): store.rename(id, to: name)
        case let .folder(id): store.renameFolder(id, to: name)
        }
    }

    private func drop(_ payloads: [String], into target: UUID?) -> Bool {
        var moved = false
        for payload in payloads {
            switch LibraryItem(dragPayload: payload) {
            case let .document(id)?:
                store.moveDocument(id, to: target)
                moved = true
            case let .folder(id)?:
                guard id != target else { continue }
                store.moveFolder(id, to: target)
                moved = true
            case nil:
                continue
            }
        }
        return moved
    }
}

/// Folder tree picker used by "Move to…".
struct MoveToFolderView: View {
    let item: LibraryItem
    @EnvironmentObject private var store: DocumentStore
    @Environment(\.dismiss) private var dismiss

    private struct Row: Identifiable {
        var id: String
        var folderID: UUID?
        var name: String
        var depth: Int
    }

    /// Folders the item may not move into (a folder can't go inside itself).
    private var excluded: Set<UUID> {
        if case let .folder(id) = item { return store.descendants(of: id) }
        return []
    }

    private var currentLocation: UUID? {
        switch item {
        case let .document(id): return store.summaries.first { $0.id == id }?.folderID
        case let .folder(id): return store.folder(id)?.parentID
        }
    }

    private var rows: [Row] {
        var result = [Row(id: "root", folderID: nil, name: "Documents", depth: 0)]
        func add(_ parent: UUID?, depth: Int) {
            for f in store.subfolders(of: parent) where !excluded.contains(f.id) {
                result.append(Row(id: f.id.uuidString, folderID: f.id, name: f.name, depth: depth))
                add(f.id, depth: depth + 1)
            }
        }
        add(nil, depth: 1)
        return result
    }

    var body: some View {
        NavigationStack {
            List(rows) { row in
                Button {
                    move(to: row.folderID)
                } label: {
                    HStack {
                        Image(systemName: row.folderID == nil ? "tray.full" : "folder")
                            .foregroundStyle(.tint)
                        Text(row.name).foregroundStyle(.primary)
                        Spacer()
                        if row.folderID == currentLocation {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                    .padding(.leading, CGFloat(row.depth) * 20)
                }
            }
            .navigationTitle("Move to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func move(to folder: UUID?) {
        switch item {
        case let .document(id): store.moveDocument(id, to: folder)
        case let .folder(id): store.moveFolder(id, to: folder)
        }
        dismiss()
    }
}
