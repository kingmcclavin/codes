import SwiftUI

/// What the Basis sidebar has selected.
enum SidebarItem: Hashable {
    case allDocuments
    case folder(UUID)
    case calculator, formulas, tools, data, history, settings

    var isNotes: Bool {
        switch self {
        case .allDocuments, .folder: return true
        default: return false
        }
    }

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
    @State private var showAppearance = false

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Calculator", systemImage: "plus.forwardslash.minus").tag(SidebarItem.calculator)
                Label("Formulas", systemImage: "function").tag(SidebarItem.formulas)
                Label("Tools", systemImage: "wrench.and.screwdriver").tag(SidebarItem.tools)
                Label("Data", systemImage: "tablecells").tag(SidebarItem.data)
                Label("History", systemImage: "clock.arrow.circlepath").tag(SidebarItem.history)
            }

            Section("Notes") {
                Label("All Notes", systemImage: "tray.full")
                    .badge(store.documents(in: nil).count)
                    .tag(SidebarItem.allDocuments)
                    .dropDestination(for: String.self) { items, _ in drop(items, into: nil) }
            }

            Section("Folders") {
                OutlineGroup(FolderNode.tree(from: store), children: \.children) { node in
                    Label {
                        Text(node.folder.name)
                    } icon: {
                        Image(systemName: node.folder.icon ?? "folder")
                            .foregroundStyle(node.folder.color.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.tint))
                    }
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
        .navigationTitle("Basis")
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    selection = .settings
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.titleAndIcon)
                        .font(.footnote)
                }
            }
        }
        .sheet(isPresented: $showExport) { ExportView() }
        .sheet(isPresented: $showAppearance) { AppearanceSettingsView() }
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

/// Slim, browser-style strip of open documents shown above a notebook.
/// Tabs are plain titles; the active one is marked with an underline and is
/// the only one showing a close button.
struct DocumentTabBar: View {
    @EnvironmentObject private var tabs: TabsModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(tabs.tabs, id: \.self) { id in
                        DocumentTab(id: id, title: tabs.title(for: id), isActive: tabs.activeID == id)
                            .id(id)
                    }
                }
                .padding(.horizontal, 10)
            }
            .onChange(of: tabs.activeID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id) }
            }
        }
        .frame(height: 30)
        .background(.bar)
    }
}

private struct DocumentTab: View {
    let id: UUID
    let title: String
    let isActive: Bool
    @EnvironmentObject private var tabs: TabsModel

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(isActive ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)
            if isActive {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { tabs.close(id) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Close \(title)")
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: 180, minHeight: 30)
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(isActive ? Color.appAccent : .clear)
                .frame(height: 2)
                .padding(.horizontal, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture { tabs.activate(id) }
        .contextMenu {
            Button("Close Tab", systemImage: "xmark") { tabs.close(id) }
            Button("Close Other Tabs", systemImage: "xmark.square") { tabs.closeOthers(id) }
        }
    }
}
