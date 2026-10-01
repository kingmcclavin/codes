import SwiftUI

/// Details + management for one app: active build, build history / version
/// switching, compatibility report, metadata, and data operations.
struct AppDetailsView: View {
    @EnvironmentObject var library: AppLibraryManager
    @Environment(\.dismiss) private var dismiss

    let appID: UUID
    let onLaunch: (ContainerApp) -> Void

    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var confirmDeleteBuild: AppVersion?

    private var app: ContainerApp? { library.binding(for: appID) }

    var body: some View {
        Group {
            if let app {
                content(app)
            } else {
                ContentUnavailableCompat(title: "App Removed",
                                         systemImage: "trash",
                                         message: "This app is no longer in the library.")
            }
        }
        .navigationTitle(app?.displayLabel ?? "App")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .sheet(isPresented: $showShare) {
            if let shareURL { ShareSheet(items: [shareURL]) }
        }
    }

    @ViewBuilder
    private func content(_ app: ContainerApp) -> some View {
        List {
            headerSection(app)
            launchSection(app)
            buildHistorySection(app)
            compatibilitySection(app)
            metadataSection(app)
            dataSection(app)
            dangerSection(app)
        }
        .listStyle(.insetGrouped)
        .confirmationDialog("Delete this build?",
                            isPresented: Binding(get: { confirmDeleteBuild != nil },
                                                 set: { if !$0 { confirmDeleteBuild = nil } }),
                            presenting: confirmDeleteBuild) { build in
            Button("Delete Build \(build.buildNumber)", role: .destructive) {
                library.deleteBuild(appID: app.id, versionID: build.id)
                confirmDeleteBuild = nil
            }
            Button("Cancel", role: .cancel) { confirmDeleteBuild = nil }
        }
    }

    // MARK: Sections

    private func headerSection(_ app: ContainerApp) -> some View {
        Section {
            HStack(spacing: 14) {
                AppIconView(app: app, size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.displayLabel).font(.title3.bold())
                    Text(app.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                    Text(app.activeVersion.displayVersion).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    library.toggleFavorite(appID: app.id)
                } label: {
                    Image(systemName: app.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(app.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func launchSection(_ app: ContainerApp) -> some View {
        Section {
            Button {
                onLaunch(app)
            } label: {
                Label("Launch Active Build", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            if let report = app.activeVersion.compatibility, !report.runtimeLaunchable {
                Label("Runs in inspection mode (see Compatibility).",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func buildHistorySection(_ app: ContainerApp) -> some View {
        Section("Build History") {
            ForEach(app.versionsNewestFirst) { v in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Build \(v.buildNumber)")
                            .font(.body.weight(v.id == app.activeVersionID ? .semibold : .regular))
                        Text("v\(v.version) · \(v.importDate, style: .date)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(ByteCountFormatter.string(fromByteCount: v.ipaSizeBytes, countStyle: .file))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if v.id == app.activeVersionID {
                        Label("Current", systemImage: "star.fill")
                            .font(.caption).foregroundStyle(.yellow)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Button("Make Active") {
                            library.setActiveVersion(appID: app.id, versionID: v.id)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }
                .swipeActions {
                    if app.versions.count > 1 {
                        Button(role: .destructive) { confirmDeleteBuild = v } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func compatibilitySection(_ app: ContainerApp) -> some View {
        if let report = app.activeVersion.compatibility {
            Section("Compatibility") {
                HStack {
                    Image(systemName: report.level.symbolName)
                        .foregroundStyle(color(for: report.level))
                    Text(report.summaryLine).font(.headline)
                }
                ForEach(report.checks) { check in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: check.status.symbol)
                            .foregroundStyle(color(for: check.status))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.title)
                            if let detail = check.detail {
                                Text(detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label(report.runtimeLaunchable ? "Runtime: can launch"
                                                   : "Runtime: cannot execute natively",
                          systemImage: report.runtimeLaunchable ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.subheadline.bold())
                        .foregroundStyle(report.runtimeLaunchable ? .green : .orange)
                    Text(report.runtimeExplanation)
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func metadataSection(_ app: ContainerApp) -> some View {
        let m = app.activeVersion.metadata
        return Section("Information") {
            infoRow("Display Name", m.displayName)
            infoRow("Bundle ID", m.bundleIdentifier)
            infoRow("Version", m.version)
            infoRow("Build", m.buildNumber)
            infoRow("Minimum iOS", m.minimumOSVersion)
            infoRow("Device Family", m.deviceFamilyLabel)
            infoRow("Architectures", m.architectures.isEmpty ? "unknown" : m.architectures.joined(separator: ", "))
            infoRow("Bundle Size", m.formattedBundleSize)
            if !m.appExtensions.isEmpty {
                infoRow("Extensions", m.appExtensions.joined(separator: ", "))
            }
            if !m.entitlementKeys.isEmpty {
                DisclosureGroup("Entitlements (\(m.entitlementKeys.count))") {
                    ForEach(m.entitlementKeys, id: \.self) { key in
                        Text(key).font(.caption.monospaced())
                    }
                }
            }
        }
    }

    private func dataSection(_ app: ContainerApp) -> some View {
        let dataSize = AppDataManager.dataSize(for: app, version: app.activeVersion)
        return Section("App Data (active build)") {
            infoRow("Data Size", ByteCountFormatter.string(fromByteCount: dataSize, countStyle: .file))
            Button {
                try? AppDataManager.clearData(for: app, version: app.activeVersion)
            } label: { Label("Clear Data", systemImage: "trash.slash") }
            Button {
                try? AppDataManager.resetApp(for: app, version: app.activeVersion)
            } label: { Label("Reset App", systemImage: "arrow.counterclockwise") }
            Button {
                if let url = try? AppDataManager.exportDiagnostics(for: app) {
                    shareURL = url; showShare = true
                }
            } label: { Label("Export Diagnostics", systemImage: "square.and.arrow.up") }
            Text("Note: data isolation here is best-effort within this container's own sandbox — not the same as an independently-installed app.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func dangerSection(_ app: ContainerApp) -> some View {
        Section {
            Button(role: .destructive) {
                library.deleteApp(appID: app.id)
                dismiss()
            } label: {
                Label("Delete App & All Builds", systemImage: "trash")
            }
        }
    }

    // MARK: Helpers

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
    }

    private func color(for level: CompatibilityReport.Level) -> Color {
        switch level {
        case .good: return .green
        case .limited: return .orange
        case .unsupported: return .red
        }
    }
    private func color(for status: CompatibilityReport.Check.Status) -> Color {
        switch status {
        case .pass: return .green
        case .warn: return .orange
        case .fail: return .red
        case .info: return .secondary
        }
    }
}

/// Minimal cross-version stand-in for ContentUnavailableView (iOS 17+).
struct ContentUnavailableCompat: View {
    let title: String
    let systemImage: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
