import Foundation

/// Manages each build's isolated data directory and the operations the brief
/// asks for: Clear Data, Reset App, Preserve Data (export), Delete Build.
///
/// IMPORTANT (documented in the UI too): this is *best-effort* isolation inside
/// the container's own sandbox. It is NOT the same as the per-app sandbox iOS
/// gives independently-installed applications.
enum AppDataManager {

    static func dataDirectory(for app: ContainerApp, version: AppVersion) -> URL {
        ContainerStorage.shared.absoluteURL(forRelative: version.dataRelativePath)
    }

    static func clearData(for app: ContainerApp, version: AppVersion) throws {
        try ContainerStorage.shared.clearData(bundleID: app.bundleIdentifier, versionID: version.id)
        DiagnosticLogger.shared.log(.fileSystem,
            "Cleared data for \(app.displayLabel) \(version.displayVersion)")
    }

    /// Reset = clear data (alias kept for the UI's "Reset App" action, which may
    /// later also clear caches/preferences selectively).
    static func resetApp(for app: ContainerApp, version: AppVersion) throws {
        try clearData(for: app, version: version)
        DiagnosticLogger.shared.log(.fileSystem,
            "Reset \(app.displayLabel) \(version.displayVersion)")
    }

    static func dataSize(for app: ContainerApp, version: AppVersion) -> Int64 {
        let dir = dataDirectory(for: app, version: version)
        return ContainerStorage.shared.directorySize(at: dir)
    }

    /// Write a diagnostic bundle (metadata + log tail) to a temp file and return
    /// its URL so the caller can present a share sheet. Nothing leaves the device
    /// unless the *user* chooses a destination in the share sheet.
    static func exportDiagnostics(for app: ContainerApp) throws -> URL {
        var text = """
        TestApps — Diagnostic Export
        Generated: \(ISO8601DateFormatter().string(from: Date()))

        App: \(app.displayLabel)
        Bundle ID: \(app.bundleIdentifier)
        Builds: \(app.versions.count)
        Favorite: \(app.isFavorite)
        Last launched: \(app.lastLaunched.map { ISO8601DateFormatter().string(from: $0) } ?? "never")

        """
        for v in app.versionsNewestFirst {
            text += """
            --- Build \(v.buildNumber) (v\(v.version)) ---
            Imported: \(ISO8601DateFormatter().string(from: v.importDate))
            Min iOS: \(v.metadata.minimumOSVersion)
            Architectures: \(v.metadata.architectures.joined(separator: ", "))
            Extensions: \(v.metadata.appExtensions.joined(separator: ", "))
            Entitlements: \(v.metadata.entitlementKeys.joined(separator: ", "))
            IPA size: \(ByteCountFormatter.string(fromByteCount: v.ipaSizeBytes, countStyle: .file))
            Data size: \(ByteCountFormatter.string(fromByteCount: dataSize(for: app, version: v), countStyle: .file))
            Compatibility: \(v.compatibility?.level.rawValue ?? "n/a")

            """
        }
        text += "\n--- Recent log ---\n"
        text += DiagnosticLogger.shared.exportText().suffix(8000)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestApps-\(app.bundleIdentifier)-diagnostics.txt")
        try text.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }
}
