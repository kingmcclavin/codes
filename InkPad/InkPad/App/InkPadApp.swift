import SwiftUI

@main
struct InkPadApp: App {
    @StateObject private var store = DocumentStore.shared
    @StateObject private var preferences = AppPreferences.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(preferences)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var preferences: AppPreferences
    @State private var path: [LibraryRoute] = []
    @State private var didRestore = false

    var body: some View {
        NavigationStack(path: $path) {
            LibraryView(folderID: nil, navigate: { path.append($0) })
                .navigationDestination(for: LibraryRoute.self) { route in
                    switch route {
                    case let .folder(id):
                        LibraryView(folderID: id, navigate: { path.append($0) })
                    case let .document(id):
                        DocumentLoaderView(documentID: id)
                            .toolbar(.hidden, for: .navigationBar)
                    }
                }
        }
        .onAppear {
            store.reload()
            // Reopen the document the user was working in, inside its folder.
            guard !didRestore else { return }
            didRestore = true
            if let id = preferences.lastOpenedDocumentID, store.exists(id) {
                let folder = store.summaries.first { $0.id == id }?.folderID
                path = store.path(to: folder).map { LibraryRoute.folder($0.id) } + [LibraryRoute.document(id)]
            }
        }
        .onChange(of: path) { _, newValue in
            if case let .document(id)? = newValue.last {
                preferences.lastOpenedDocumentID = id
            } else {
                preferences.lastOpenedDocumentID = nil
                store.reload()
            }
        }
    }
}

/// Loads a document off the main thread, then shows the editor.
struct DocumentLoaderView: View {
    let documentID: UUID
    @EnvironmentObject private var store: DocumentStore
    @State private var editor: EditorModel?
    @State private var error: String?

    var body: some View {
        Group {
            if let editor {
                EditorView(editor: editor)
            } else if let error {
                ContentUnavailableView("Can't Open Document", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .task(id: documentID) {
            guard editor == nil else { return }
            let store = self.store
            let id = documentID
            let result = await Task.detached(priority: .userInitiated) { () -> Result<DocumentModel, Error> in
                Result { try store.load(id) }
            }.value
            switch result {
            case let .success(doc): editor = EditorModel(document: doc, store: store)
            case let .failure(e): error = e.localizedDescription
            }
        }
    }
}
