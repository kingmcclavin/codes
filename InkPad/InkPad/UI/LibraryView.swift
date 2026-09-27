import SwiftUI

/// Simple document list – deliberately no covers or thumbnails.
struct LibraryView: View {
    let open: (UUID) -> Void
    @EnvironmentObject private var store: DocumentStore
    @State private var showNew = false
    @State private var renaming: DocumentSummary?
    @State private var renameText = ""
    @State private var search = ""

    private var filtered: [DocumentSummary] {
        search.isEmpty ? store.summaries : store.summaries.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        Group {
            if store.summaries.isEmpty {
                ContentUnavailableView {
                    Label("No Documents", systemImage: "pencil.and.scribble")
                } description: {
                    Text("Create a document to start writing.")
                } actions: {
                    Button("New Document") { showNew = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(filtered) { doc in
                        Button { open(doc.id) } label: { row(doc) }
                            .contextMenu {
                                Button("Rename", systemImage: "pencil") { renameText = doc.title; renaming = doc }
                                Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicate(doc.id) }
                                Button("Delete", systemImage: "trash", role: .destructive) { store.delete(doc.id) }
                            }
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { store.delete(doc.id) }
                            }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $search)
            }
        }
        .navigationTitle("Documents")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNew = true } label: { Label("New Document", systemImage: "square.and.pencil") }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $showNew) {
            NewDocumentView { id in
                showNew = false
                open(id)
            }
        }
        .alert("Rename Document", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let doc = renaming { store.rename(doc.id, to: renameText.isEmpty ? doc.title : renameText) }
                renaming = nil
            }
        }
    }

    private func row(_ doc: DocumentSummary) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.text")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(doc.title.isEmpty ? "Untitled" : doc.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text("\(doc.pageCount) page\(doc.pageCount == 1 ? "" : "s") · \(PaperSize.describe(doc.pageSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(doc.modifiedAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
