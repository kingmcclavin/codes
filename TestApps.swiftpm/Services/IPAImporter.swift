import Foundation

/// Low-level import pipeline: take a user-picked `.ipa` URL, copy its bytes into
/// a new build directory in our container, parse metadata, extract the icon, and
/// build an `AppVersion`. Higher-level grouping/version decisions live in
/// `AppLibraryManager`.
enum IPAImporter {

    struct ImportedBuild {
        let version: AppVersion
        let metadata: AppMetadata
    }

    enum ImportError: LocalizedError {
        case accessDenied
        case copyFailed(String)
        case parseFailed(String)

        var errorDescription: String? {
            switch self {
            case .accessDenied: return "Could not access the selected file."
            case .copyFailed(let w): return "Failed to copy the IPA: \(w)"
            case .parseFailed(let w): return "Failed to read the IPA: \(w)"
            }
        }
    }

    /// Import an IPA from a (possibly security-scoped) URL returned by the
    /// document picker. Runs off the main actor.
    static func importIPA(from pickedURL: URL) throws -> ImportedBuild {
        let storage = ContainerStorage.shared
        let fm = FileManager.default

        // The picker hands back a security-scoped URL; we must start access.
        let scoped = pickedURL.startAccessingSecurityScopedResource()
        defer { if scoped { pickedURL.stopAccessingSecurityScopedResource() } }

        // First parse from the original location to learn the bundle id / build,
        // so we can place it in the right directory.
        DiagnosticLogger.shared.log(.importer, "Reading \(pickedURL.lastPathComponent)…")
        let parsed: ParsedIPA
        do {
            parsed = try IPAParser.parse(ipaURL: pickedURL)
        } catch {
            throw ImportError.parseFailed(error.localizedDescription)
        }
        let meta = parsed.metadata
        DiagnosticLogger.shared.log(.importer,
            "Parsed \(meta.displayName) \(meta.versionLabel) [\(meta.bundleIdentifier)]")

        // Allocate a new version id + directory.
        let versionID = UUID()
        let versionDir: URL
        do {
            versionDir = try storage.versionDirectory(
                bundleID: meta.bundleIdentifier, versionID: versionID, create: true)
        } catch {
            throw ImportError.copyFailed(error.localizedDescription)
        }

        // Copy the IPA bytes into our container.
        let destIPA = versionDir.appendingPathComponent("app.ipa")
        do {
            if fm.fileExists(atPath: destIPA.path) { try fm.removeItem(at: destIPA) }
            try fm.copyItem(at: pickedURL, to: destIPA)
        } catch {
            throw ImportError.copyFailed(error.localizedDescription)
        }
        let ipaSize = fileSize(at: destIPA)

        // Extract and save the icon.
        var iconRelative: String?
        if let pngData = IconExtractor.extractIconPNG(from: parsed) {
            let iconURL = versionDir.appendingPathComponent("icon.png")
            do {
                try pngData.write(to: iconURL, options: .atomic)
                iconRelative = storage.relativePath(for: iconURL)
                DiagnosticLogger.shared.log(.importer, "Icon extracted (\(pngData.count) bytes)")
            } catch {
                DiagnosticLogger.shared.log(.fileSystem,
                    "Icon save failed: \(error.localizedDescription)")
            }
        } else {
            DiagnosticLogger.shared.log(.importer, "No icon found; using placeholder.")
        }

        // Create the isolated data directory.
        let dataDir = try storage.makeDataDirectory(
            bundleID: meta.bundleIdentifier, versionID: versionID)

        // Compatibility snapshot.
        let report = CompatibilityChecker.evaluate(parsed)

        let version = AppVersion(
            id: versionID,
            version: meta.version,
            buildNumber: meta.buildNumber,
            importDate: Date(),
            ipaRelativePath: storage.relativePath(for: destIPA),
            iconRelativePath: iconRelative,
            dataRelativePath: storage.relativePath(for: dataDir),
            metadata: meta,
            compatibility: report,
            ipaSizeBytes: ipaSize)

        return ImportedBuild(version: version, metadata: meta)
    }

    private static func fileSize(at url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
