import SwiftUI
import Combine

/// The virtual Home Screen — an iOS-style launcher *inside* the container.
struct HomeScreenView: View {
    @EnvironmentObject var library: AppLibraryManager

    let onImport: () -> Void
    let onOpenDetails: (ContainerApp) -> Void
    let onLaunch: (ContainerApp) -> Void
    let onOpenSettings: () -> Void
    let onOpenConsole: () -> Void

    @State private var searchText = ""
    @State private var now = Date()
    @State private var openFolder: HomeFolder?
    @State private var renameTarget: ContainerApp?
    @State private var renameText = ""

    private let clockTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 20)]
    }

    private var topLevelApps: [ContainerApp] {
        let base = library.apps(inFolder: nil)
        guard !searchText.isEmpty else { return base }
        return library.apps.filter {
            $0.displayLabel.localizedCaseInsensitiveContains(searchText)
            || $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if !library.recents.isEmpty && searchText.isEmpty {
                            section("Recently Used", apps: Array(library.recents.prefix(6)))
                        }
                        if !library.favorites.isEmpty && searchText.isEmpty {
                            section("Favorites", apps: library.favorites)
                        }

                        // Folders (only when not searching)
                        if searchText.isEmpty && !library.folders.isEmpty {
                            foldersSection
                        }

                        mainGrid
                    }
                    .padding(20)
                }
            }
        }
        .onReceive(clockTimer) { now = $0 }
        .sheet(item: $openFolder) { folder in
            FolderView(folder: folder,
                       onOpenDetails: onOpenDetails,
                       onLaunch: onLaunch)
        }
        .alert("Rename", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } })) {
            TextField("Label", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") {
                if let t = renameTarget { library.rename(appID: t.id, to: renameText) }
                renameTarget = nil
            }
        }
    }

    // MARK: Pieces

    private var background: some View {
        LinearGradient(colors: [Color(.systemBackground),
                                Color.blue.opacity(0.08),
                                Color.purple.opacity(0.08)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(now, style: .time)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                    Text("My Test Apps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onOpenConsole) {
                    Image(systemName: "terminal").font(.title3)
                }
                .padding(.trailing, 4)
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape").font(.title3)
                }
            }
            searchBar
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search apps", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func section(_ title: String, apps: [ContainerApp]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(apps) { app in iconCell(app) }
            }
        }
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Folders").font(.headline)
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(library.folders.sorted { $0.sortIndex < $1.sortIndex }) { folder in
                    Button { openFolder = folder } label: {
                        VStack(spacing: 6) {
                            FolderIcon(folder: folder)
                            Text(folder.name).font(.caption).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            library.deleteFolder(folder.id)
                        } label: { Label("Delete Folder", systemImage: "trash") }
                    }
                }
            }
        }
    }

    private var mainGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !searchText.isEmpty {
                Text("Results").font(.headline)
            } else if !library.folders.isEmpty || !library.favorites.isEmpty {
                Text("All Apps").font(.headline)
            }
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(topLevelApps) { app in iconCell(app) }
                importCell
            }
            if library.apps.isEmpty {
                emptyState
            }
            pageDots
        }
    }

    private func iconCell(_ app: ContainerApp) -> some View {
        VStack(spacing: 6) {
            Button { onLaunch(app) } label: {
                AppIconView(app: app, size: 64)
            }
            .buttonStyle(.plain)
            Text(app.displayLabel)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 88)
            Text(app.activeVersion.displayVersion)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contextMenu { contextMenu(for: app) }
    }

    @ViewBuilder
    private func contextMenu(for app: ContainerApp) -> some View {
        Button { onLaunch(app) } label: { Label("Launch", systemImage: "play.fill") }
        Button { onOpenDetails(app) } label: { Label("App Info", systemImage: "info.circle") }
        Button {
            library.toggleFavorite(appID: app.id)
        } label: {
            Label(app.isFavorite ? "Unfavorite" : "Favorite",
                  systemImage: app.isFavorite ? "star.slash" : "star")
        }
        Button {
            renameText = app.displayLabel
            renameTarget = app
        } label: { Label("Rename", systemImage: "pencil") }

        if !library.folders.isEmpty {
            Menu {
                Button("None") { library.move(appID: app.id, toFolder: nil) }
                ForEach(library.folders) { f in
                    Button(f.name) { library.move(appID: app.id, toFolder: f.id) }
                }
            } label: { Label("Move to Folder", systemImage: "folder") }
        }
        Button { library.duplicateApp(appID: app.id) } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        Divider()
        Button(role: .destructive) { library.deleteApp(appID: app.id) } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var importCell: some View {
        VStack(spacing: 6) {
            Button(action: onImport) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, height: 64)
                    .overlay(Image(systemName: "plus").font(.title).foregroundStyle(.secondary))
            }
            .buttonStyle(.plain)
            Text("Import IPA").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 42)).foregroundStyle(.secondary)
            Text("No apps yet")
                .font(.headline)
            Text("Tap Import IPA to add your first build.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            Circle().frame(width: 7, height: 7).foregroundStyle(.primary)
            Circle().frame(width: 7, height: 7).foregroundStyle(.secondary.opacity(0.4))
            Circle().frame(width: 7, height: 7).foregroundStyle(.secondary.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
}

// MARK: - Folder icon + folder contents

struct FolderIcon: View {
    @EnvironmentObject var library: AppLibraryManager
    let folder: HomeFolder
    var body: some View {
        let apps = library.apps(inFolder: folder.id).prefix(4)
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.ultraThinMaterial)
            .frame(width: 64, height: 64)
            .overlay(
                LazyVGrid(columns: [GridItem(.fixed(22)), GridItem(.fixed(22))], spacing: 4) {
                    ForEach(Array(apps)) { app in
                        AppIconView(app: app, size: 22)
                    }
                }
                .padding(6)
            )
    }
}

struct FolderView: View {
    @EnvironmentObject var library: AppLibraryManager
    @Environment(\.dismiss) private var dismiss
    let folder: HomeFolder
    let onOpenDetails: (ContainerApp) -> Void
    let onLaunch: (ContainerApp) -> Void

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 20)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(library.apps(inFolder: folder.id)) { app in
                        VStack(spacing: 6) {
                            Button { onLaunch(app); dismiss() } label: {
                                AppIconView(app: app, size: 64)
                            }.buttonStyle(.plain)
                            Text(app.displayLabel).font(.caption).lineLimit(1)
                        }
                        .contextMenu {
                            Button { onOpenDetails(app); dismiss() } label: {
                                Label("App Info", systemImage: "info.circle")
                            }
                            Button { library.move(appID: app.id, toFolder: nil) } label: {
                                Label("Remove from Folder", systemImage: "folder.badge.minus")
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(folder.name)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            } }
        }
    }
}
