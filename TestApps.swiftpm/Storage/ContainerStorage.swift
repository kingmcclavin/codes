import Foundation

/// Owns the on-disk layout inside the app's private container (Application Support).
///
/// Layout:
/// ```
/// <AppSupport>/TestApps/
///   library.json                      (PersistenceManager)
///   Apps/
///     <bundleId>/
///       <versionUUID>/
///         app.ipa                      stored IPA for the build
///         icon.png                     extracted icon
///         Data/                        isolated data dir for the build
///           Documents/ Library/ Preferences/ tmp/
/// ```
///
/// All of this lives in the container app's own sandbox. See `SAFETY` notes in
/// README: this is *not* the same isolation iOS gives independently-installed apps.
final class ContainerStorage {
    static let shared = ContainerStorage()

    let rootURL: URL
    let appsURL: URL

    private let fm = FileManager.default

    private init() {
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true))
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask)[0]

        rootURL = base.appendingPathComponent("TestApps", isDirectory: true)
        appsURL = rootURL.appendingPathComponent("Apps", isDirectory: true)
        try? ensureDirectories()
    }

    private func ensureDirectories() throws {
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: appsURL, withIntermediateDirectories: true)
    }

    var libraryFileURL: URL { rootURL.appendingPathComponent("library.json") }

    // MARK: Relative <-> absolute

    /// Resolve a path stored relative to the library root into an absolute URL.
    func absoluteURL(forRelative path: String) -> URL {
        rootURL.appendingPathComponent(path)
    }

    /// Make a URL under the root relative for stable, movable storage records.
    func relativePath(for url: URL) -> String {
        let rootStd = rootURL.standardizedFileURL.path
        let urlStd = url.standardizedFileURL.path
        if urlStd.hasPrefix(rootStd) {
            return String(urlStd.dropFirst(rootStd.count).drop(while: { $0 == "/" }))
        }
        return urlStd
    }

    // MARK: Per-build directories

    func versionDirectory(bundleID: String, versionID: UUID, create: Bool = false) throws -> URL {
        let dir = appsURL
            .appendingPathComponent(sanitize(bundleID), isDirectory: true)
            .appendingPathComponent(versionID.uuidString, isDirectory: true)
        if create { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        return dir
    }

    /// Create the isolated data directory tree for a build and return it.
    @discardableResult
    func makeDataDirectory(bundleID: String, versionID: UUID) throws -> URL {
        let dir = try versionDirectory(bundleID: bundleID, versionID: versionID, create: true)
            .appendingPathComponent("Data", isDirectory: true)
        for sub in ["Documents", "Library", "Library/Preferences", "Library/Caches", "tmp"] {
            try fm.createDirectory(at: dir.appendingPathComponent(sub),
                                   withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: Deletion / size

    func removeVersion(bundleID: String, versionID: UUID) {
        let dir = try? versionDirectory(bundleID: bundleID, versionID: versionID)
        if let dir { try? fm.removeItem(at: dir) }
    }

    func removeAppTree(bundleID: String) {
        let dir = appsURL.appendingPathComponent(sanitize(bundleID), isDirectory: true)
        try? fm.removeItem(at: dir)
    }

    func clearData(bundleID: String, versionID: UUID) throws {
        let dataDir = try versionDirectory(bundleID: bundleID, versionID: versionID)
            .appendingPathComponent("Data", isDirectory: true)
        if fm.fileExists(atPath: dataDir.path) {
            try fm.removeItem(at: dataDir)
        }
        try makeDataDirectory(bundleID: bundleID, versionID: versionID)
    }

    func directorySize(at url: URL) -> Int64 {
        guard let e = fm.enumerator(at: url,
                                    includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in e {
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }

    func totalLibrarySize() -> Int64 { directorySize(at: appsURL) }

    private func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "_")
         .replacingOccurrences(of: "..", with: "_")
    }
}
