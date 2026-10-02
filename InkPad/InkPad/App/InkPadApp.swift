import SwiftUI

@main
struct InkPadApp: App {
    @StateObject private var store = DocumentStore.shared
    @StateObject private var preferences = AppPreferences.shared
    @StateObject private var tabs = TabsModel(store: .shared)
    @StateObject private var calculator = CalculatorStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(preferences)
                .environmentObject(tabs)
                .environmentObject(calculator)
        }
    }
}

/// Either the library (folder sidebar + list) or the active document, with
/// a slim tab strip above documents when several are open.
struct RootView: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var tabs: TabsModel
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var calculator: CalculatorStore
    @State private var sidebarSelection: SidebarItem? = .allDocuments
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var didRestore = false
    @AppStorage("proToolsEnabled") private var proTools = false

    var body: some View {
        VStack(spacing: 0) {
            // Only inside a notebook, and only when there is something to switch to.
            if !tabs.showsLibrary && tabs.tabs.count > 1 {
                DocumentTabBar()
                Divider()
            }
            ZStack {
                library
                    .opacity(tabs.showsLibrary ? 1 : 0)
                    .allowsHitTesting(tabs.showsLibrary)
                if let id = tabs.activeID {
                    documentView(id)
                        .id(id)
                        .transition(.opacity)
                }
            }
        }
        .tint(preferences.accentColor?.color)
        .onAppear {
            guard !didRestore else { return }
            didRestore = true
            store.reload()
            tabs.restore()
        }
        .onChange(of: store.summaries) { _, docs in
            tabs.prune(existing: Set(docs.map(\.id)))
        }
        .onChange(of: store.folders) { _, folders in
            if let id = sidebarSelection?.folderID, !folders.contains(where: { $0.id == id }) {
                sidebarSelection = .allDocuments
            }
        }
        .onChange(of: proTools) { _, enabled in
            // Leaving a Toolbox screen when Pro Tools are switched off.
            if !enabled, [.formulas, .tools, .data, .history].contains(sidebarSelection) {
                sidebarSelection = .allDocuments
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            tabs.flushAll()
            calculator.flush()
        }
    }

    /// The Basis workspace: sidebar (sections + notebook folders) and the
    /// selected section.
    private var library: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LibrarySidebar(selection: $sidebarSelection)
        } detail: {
            detail
                .environment(\.basisNavigate, { item in sidebarSelection = item })
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch sidebarSelection ?? .allDocuments {
        case .allDocuments, .folder:
            NavigationStack {
                LibraryView(folderID: sidebarSelection?.folderID, navigate: navigate)
                    .id(sidebarSelection)
            }
        case .calculator:
            NavigationStack { CalculatorView() }
        case .formulas:
            FormulaLibraryView()
        case .tools:
            ToolsView()
        case .data:
            DataHomeView()
        case .history:
            HistoryView()
        case .settings:
            BasisSettingsView()
        case .search:
            SearchView()
        }
    }

    @ViewBuilder
    private func documentView(_ id: UUID) -> some View {
        if let editor = tabs.editors[id] {
            EditorView(editor: editor, onClose: { tabs.showLibrary() })
        } else if let error = tabs.loadErrors[id] {
            ContentUnavailableView("Can't Open Document", systemImage: "exclamationmark.triangle", description: Text(error))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground))
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground))
        }
    }

    private func navigate(_ route: LibraryRoute) {
        switch route {
        case .library: sidebarSelection = .allDocuments
        case let .folder(id): sidebarSelection = .folder(id)
        case let .document(id): tabs.open(id)
        }
    }
}
