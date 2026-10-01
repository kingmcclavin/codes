import SwiftUI

/// A list-style management view (reachable from Settings) for browsing every app
/// and build, switching active versions, reordering, and deleting. Complements
/// the icon-grid Home Screen.
struct AppLibraryView: View {
    @EnvironmentObject var library: AppLibraryManager
    @State private var detailAppID: UUID?

    var body: some View {
        List {
            if library.apps.isEmpty {
                ContentUnavailableCompat(title: "No Apps",
                                         systemImage: "square.grid.2x2",
                                         message: "Import an IPA from the Home Screen.")
            }
            Section {
                ForEach(library.apps.sorted { $0.sortIndex < $1.sortIndex }) { app in
                    Button { detailAppID = app.id } label: {
                        HStack(spacing: 12) {
                            AppIconView(app: app, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.displayLabel).font(.headline)
                                Text(app.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                                Text("\(app.versions.count) build(s) · active \(app.activeVersion.displayVersion)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onMove(perform: move)
            }
        }
        .navigationTitle("Apps & Builds")
        .toolbar { EditButton() }
        .sheet(item: Binding(get: { detailAppID.map { IDBox(id: $0) } },
                             set: { detailAppID = $0?.id })) { box in
            NavigationStack {
                AppDetailsView(appID: box.id, onLaunch: { _ in detailAppID = nil })
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = library.apps.sorted { $0.sortIndex < $1.sortIndex }
        ordered.move(fromOffsets: source, toOffset: destination)
        library.reorder(appIDs: ordered.map(\.id))
    }
}

private struct IDBox: Identifiable { let id: UUID }
