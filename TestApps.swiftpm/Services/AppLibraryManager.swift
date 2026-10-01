import Foundation
import Combine

/// The single source of truth for the app library and Home Screen state.
/// All mutations persist immediately. Observable for SwiftUI.
@MainActor
final class AppLibraryManager: ObservableObject {
    static let shared = AppLibraryManager()

    @Published private(set) var apps: [ContainerApp] = []
    @Published private(set) var folders: [HomeFolder] = []
    @Published private(set) var recentBundleIDs: [String] = []
    @Published var hasAcknowledgedSafety: Bool = false

    private let persistence = PersistenceManager.shared

    private init() {
        let snap = persistence.load()
        apps = snap.apps
        folders = snap.folders
        recentBundleIDs = snap.recentBundleIDs
        hasAcknowledgedSafety = snap.hasAcknowledgedSafety
        DiagnosticLogger.shared.log(.runtime, "Library loaded: \(apps.count) app(s)")
    }

    // MARK: Persistence

    private func persist() {
        persistence.save(LibrarySnapshot(apps: apps,
                                         folders: folders,
                                         recentBundleIDs: recentBundleIDs,
                                         hasAcknowledgedSafety: hasAcknowledgedSafety))
    }

    func acknowledgeSafety() {
        hasAcknowledgedSafety = true
        persist()
    }

    // MARK: Queries

    func app(withBundleID id: String) -> ContainerApp? {
        apps.first { $0.bundleIdentifier == id }
    }

    func binding(for appID: UUID) -> ContainerApp? {
        apps.first { $0.id == appID }
    }

    var favorites: [ContainerApp] { apps.filter(\.isFavorite) }

    var recents: [ContainerApp] {
        recentBundleIDs.compactMap { id in apps.first { $0.bundleIdentifier == id } }
    }

    func apps(inFolder folderID: UUID?) -> [ContainerApp] {
        apps.filter { $0.folderID == folderID }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    // MARK: Import flow

    /// Result of importing an IPA, so the UI can present the "new version" sheet.
    enum ImportOutcome {
        /// A brand-new app (no existing bundle id). Already added.
        case addedNewApp(ContainerApp)
        /// Existing bundle id; the new build is staged and the UI must choose.
        case versionConflict(existing: ContainerApp, staged: AppVersion)
        /// Same build number already present; staged for Keep Both/Cancel.
        case duplicateBuild(existing: ContainerApp, staged: AppVersion)
    }

    /// Perform the file copy/parse off the main actor, then return an outcome to
    /// decide on the main actor.
    func importIPA(from url: URL) async throws -> ImportOutcome {
        let built = try await Task.detached(priority: .userInitiated) {
            try IPAImporter.importIPA(from: url)
        }.value

        let staged = built.version
        if let existing = app(withBundleID: built.metadata.bundleIdentifier) {
            if existing.existingVersion(matching: built.metadata) != nil {
                return .duplicateBuild(existing: existing, staged: staged)
            }
            return .versionConflict(existing: existing, staged: staged)
        } else {
            let newApp = ContainerApp(
                bundleIdentifier: built.metadata.bundleIdentifier,
                displayLabel: built.metadata.displayName,
                versions: [staged],
                activeVersionID: staged.id,
                sortIndex: apps.count)
            apps.append(newApp)
            noteRecent(built.metadata.bundleIdentifier)
            persist()
            DiagnosticLogger.shared.log(.importer, "Added new app: \(newApp.displayLabel)")
            return .addedNewApp(newApp)
        }
    }

    /// Keep both builds: append the staged version and make it active.
    func keepBothBuilds(appID: UUID, staged: AppVersion) {
        mutate(appID: appID) { app in
            app.versions.append(staged)
            app.activeVersionID = staged.id
        }
        noteRecent(bundleID(forAppID: appID))
        DiagnosticLogger.shared.log(.importer, "Kept both builds; active → build \(staged.buildNumber)")
    }

    /// Replace: remove the currently-active build (and its files), add the staged
    /// one, make it active.
    func replaceActiveBuild(appID: UUID, staged: AppVersion) {
        guard let app = binding(for: appID) else { return }
        let oldActive = app.activeVersion
        mutate(appID: appID) { a in
            a.versions.removeAll { $0.id == oldActive.id }
            a.versions.append(staged)
            a.activeVersionID = staged.id
        }
        ContainerStorage.shared.removeVersion(bundleID: app.bundleIdentifier, versionID: oldActive.id)
        noteRecent(app.bundleIdentifier)
        DiagnosticLogger.shared.log(.importer,
            "Replaced build \(oldActive.buildNumber) with \(staged.buildNumber)")
    }

    /// Cancel a staged import: delete the files that were already copied.
    func discardStaged(_ staged: AppVersion, bundleID: String) {
        ContainerStorage.shared.removeVersion(bundleID: bundleID, versionID: staged.id)
        DiagnosticLogger.shared.log(.importer, "Discarded staged build \(staged.buildNumber)")
    }

    // MARK: App operations

    func setActiveVersion(appID: UUID, versionID: UUID) {
        mutate(appID: appID) { $0.activeVersionID = versionID }
        DiagnosticLogger.shared.log(.runtime, "Active version set to \(versionID.uuidString.prefix(8))")
    }

    func rename(appID: UUID, to label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate(appID: appID) { $0.displayLabel = trimmed }
    }

    func toggleFavorite(appID: UUID) {
        mutate(appID: appID) { $0.isFavorite.toggle() }
    }

    func noteLaunched(appID: UUID) {
        mutate(appID: appID) { $0.lastLaunched = Date() }
        noteRecent(bundleID(forAppID: appID))
    }

    /// Duplicate an app entry (metadata only — shares nothing, copies the active
    /// build's IPA into a fresh app group). Useful for testing two config variants.
    func duplicateApp(appID: UUID) {
        guard let app = binding(for: appID) else { return }
        // Create a new app that references a *copy* of the active version's files.
        guard let copied = try? copyVersionFiles(of: app, version: app.activeVersion,
                                                 toBundleID: app.bundleIdentifier + ".copy") else {
            DiagnosticLogger.shared.log(.fileSystem, "Duplicate failed for \(app.displayLabel)")
            return
        }
        let newApp = ContainerApp(
            bundleIdentifier: app.bundleIdentifier + ".copy",
            displayLabel: app.displayLabel + " copy",
            versions: [copied],
            activeVersionID: copied.id,
            sortIndex: apps.count)
        apps.append(newApp)
        persist()
        DiagnosticLogger.shared.log(.importer, "Duplicated \(app.displayLabel)")
    }

    func deleteBuild(appID: UUID, versionID: UUID) {
        guard let app = binding(for: appID) else { return }
        guard app.versions.count > 1 else {
            // Last build → delete the whole app.
            deleteApp(appID: appID)
            return
        }
        ContainerStorage.shared.removeVersion(bundleID: app.bundleIdentifier, versionID: versionID)
        mutate(appID: appID) { a in
            a.versions.removeAll { $0.id == versionID }
            if a.activeVersionID == versionID {
                a.activeVersionID = a.versionsNewestFirst.first!.id
            }
        }
        DiagnosticLogger.shared.log(.importer, "Deleted build \(versionID.uuidString.prefix(8))")
    }

    func deleteApp(appID: UUID) {
        guard let app = binding(for: appID) else { return }
        ContainerStorage.shared.removeAppTree(bundleID: app.bundleIdentifier)
        apps.removeAll { $0.id == appID }
        recentBundleIDs.removeAll { $0 == app.bundleIdentifier }
        persist()
        DiagnosticLogger.shared.log(.importer, "Deleted app \(app.displayLabel)")
    }

    // MARK: Home screen arrangement

    func move(appID: UUID, toFolder folderID: UUID?) {
        mutate(appID: appID) { $0.folderID = folderID }
    }

    func reorder(appIDs: [UUID]) {
        for (index, id) in appIDs.enumerated() {
            mutate(appID: id, persistAfter: false) { $0.sortIndex = index }
        }
        persist()
    }

    @discardableResult
    func createFolder(name: String) -> HomeFolder {
        let folder = HomeFolder(name: name, sortIndex: folders.count)
        folders.append(folder)
        persist()
        return folder
    }

    func deleteFolder(_ folderID: UUID) {
        for i in apps.indices where apps[i].folderID == folderID {
            apps[i].folderID = nil
        }
        folders.removeAll { $0.id == folderID }
        persist()
    }

    // MARK: Internals

    private func mutate(appID: UUID, persistAfter: Bool = true, _ body: (inout ContainerApp) -> Void) {
        guard let idx = apps.firstIndex(where: { $0.id == appID }) else { return }
        body(&apps[idx])
        if persistAfter { persist() }
    }

    private func bundleID(forAppID appID: UUID) -> String {
        binding(for: appID)?.bundleIdentifier ?? ""
    }

    private func noteRecent(_ bundleID: String) {
        guard !bundleID.isEmpty else { return }
        recentBundleIDs.removeAll { $0 == bundleID }
        recentBundleIDs.insert(bundleID, at: 0)
        if recentBundleIDs.count > 12 { recentBundleIDs.removeLast(recentBundleIDs.count - 12) }
        persist()
    }

    /// Copy an existing version's IPA/icon/data into a new bundle-id tree and
    /// return a fresh AppVersion record pointing at the copies.
    private func copyVersionFiles(of app: ContainerApp,
                                  version: AppVersion,
                                  toBundleID newBundleID: String) throws -> AppVersion {
        let storage = ContainerStorage.shared
        let fm = FileManager.default
        let newVersionID = UUID()
        let newDir = try storage.versionDirectory(bundleID: newBundleID,
                                                  versionID: newVersionID, create: true)

        let srcIPA = storage.absoluteURL(forRelative: version.ipaRelativePath)
        let dstIPA = newDir.appendingPathComponent("app.ipa")
        try fm.copyItem(at: srcIPA, to: dstIPA)

        var iconRel: String?
        if let iconRelPath = version.iconRelativePath {
            let srcIcon = storage.absoluteURL(forRelative: iconRelPath)
            let dstIcon = newDir.appendingPathComponent("icon.png")
            if fm.fileExists(atPath: srcIcon.path) {
                try? fm.copyItem(at: srcIcon, to: dstIcon)
                iconRel = storage.relativePath(for: dstIcon)
            }
        }

        let dataDir = try storage.makeDataDirectory(bundleID: newBundleID, versionID: newVersionID)

        var meta = version.metadata
        meta.bundleIdentifier = newBundleID

        return AppVersion(
            id: newVersionID,
            version: version.version,
            buildNumber: version.buildNumber,
            importDate: Date(),
            ipaRelativePath: storage.relativePath(for: dstIPA),
            iconRelativePath: iconRel,
            dataRelativePath: storage.relativePath(for: dataDir),
            metadata: meta,
            compatibility: version.compatibility,
            ipaSizeBytes: version.ipaSizeBytes)
    }
}
