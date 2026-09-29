import SwiftUI

/// What the library sidebar has selected.
enum SidebarItem: Hashable {
    case allDocuments
    case folder(UUID)

    var folderID: UUID? {
        if case let .folder(id) = self { return id }
        return nil
    }
}

/// A folder and its subfolders, for the sidebar outline.
struct FolderNode: Identifiable, Hashable {
    let folder: Folder
    /// nil for folders without subfolders (no disclosure arrow).
    let children: [FolderNode]?

    var id: UUID { folder.id }

    static func tree(from store: DocumentStore, parent: UUID? = nil) -> [FolderNode] {
        store.subfolders(of: parent).map { f in
            let kids = tree(from: store, parent: f.id)
            return FolderNode(folder: f, children: kids.isEmpty ? nil : kids)
        }
    }
}

/// Folder tree sidebar. Folders containing folders get a disclosure arrow.
struct LibrarySidebar: View {
    @Binding var selection: SidebarItem?
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var tabs: TabsModel
    @State private var showExport = false

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("All Documents", systemImage: "tray.full")
                    .badge(store.documents(in: nil).count)
                    .tag(SidebarItem.allDocuments)
                    .dropDestination(for: String.self) { items, _ in drop(items, into: nil) }
            }

            Section("Folders") {
                OutlineGroup(FolderNode.tree(from: store), children: \.children) { node in
                    Label(node.folder.name, systemImage: "folder")
                        .badge(store.documents(in: node.folder.id).count)
                        .tag(SidebarItem.folder(node.folder.id))
                        .dropDestination(for: String.self) { items, _ in drop(items, into: node.folder.id) }
                        .contextMenu {
                            Button("New Folder Inside", systemImage: "folder.badge.plus") {
                                let f = store.createFolder(name: "New Folder", in: node.folder.id)
                                selection = .folder(f.id)
                            }
                        }
                }
                Button {
                    let f = store.createFolder(name: "New Folder", in: selection?.folderID)
                    selection = .folder(f.id)
                } label: {
                    Label("New Folder", systemImage: "plus")
                        .foregroundStyle(.tint)
                }
            }

            if !tabs.tabs.isEmpty {
                Section("Open") {
                    ForEach(tabs.tabs, id: \.self) { id in
                        Button {
                            tabs.open(id)
                        } label: {
                            Label(tabs.title(for: id), systemImage: "doc.text")
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("InkPad")
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button("Export App (.ipa)…", systemImage: "app.badge") { showExport = true }
                    .labelStyle(.titleAndIcon)
                    .font(.footnote)
            }
        }
        .sheet(isPresented: $showExport) { ExportView() }
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

/// Browser-style strip of open documents.
struct DocumentTabBar: View {
    @EnvironmentObject private var tabs: TabsModel

    var body: some View {
        HStack(spacing: 0) {
            Button {
                tabs.showLibrary()
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 44, height: 34)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(tabs.showsLibrary ? Color(uiColor: .systemBackground) : .clear))
            }
            .buttonStyle(.plain)
            .foregroundStyle(tabs.showsLibrary ? Color.accentColor : .secondary)
            .accessibilityLabel("Library")
            .padding(.leading, 8)

            Divider().frame(height: 20).padding(.horizontal, 6)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(tabs.tabs, id: \.self) { id in
                            DocumentTab(id: id, title: tabs.title(for: id), isActive: tabs.activeID == id)
                                .id(id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: tabs.activeID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id) }
                }
            }

            Button {
                tabs.showLibrary()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 40, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Open Another Document")
            .padding(.trailing, 6)
        }
        .frame(height: 42)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct DocumentTab: View {
    let id: UUID
    let title: String
    let isActive: Bool
    @EnvironmentObject private var tabs: TabsModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
            Text(title)
                .font(.subheadline.weight(isActive ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)
            Button {
                withAnimation(.easeOut(duration: 0.15)) { tabs.close(id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Close \(title)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(minWidth: 120, maxWidth: 220, minHeight: 34)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color(uiColor: .systemBackground) : Color.primary.opacity(0.04))
                .shadow(color: .black.opacity(isActive ? 0.08 : 0), radius: 2, y: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { tabs.activate(id) }
        .contextMenu {
            Button("Close Tab", systemImage: "xmark") { tabs.close(id) }
            Button("Close Other Tabs", systemImage: "xmark.square") { tabs.closeOthers(id) }
        }
    }
}
