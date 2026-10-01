import Foundation

/// A single imported build of an application.
///
/// A `ContainerApp` groups many `AppVersion`s that share a bundle identifier,
/// which is what makes multi-build / version management possible.
struct AppVersion: Codable, Hashable, Identifiable {
    let id: UUID
    var version: String       // CFBundleShortVersionString, e.g. "1.0"
    var buildNumber: String   // CFBundleVersion, e.g. "14"
    var importDate: Date

    /// Path, *relative to the library root*, of the stored `.ipa` for this build.
    var ipaRelativePath: String

    /// Path, *relative to the library root*, of the extracted icon PNG (if any).
    var iconRelativePath: String?

    /// Path, *relative to the library root*, of this build's isolated data dir.
    var dataRelativePath: String

    /// Full metadata snapshot captured at import time.
    var metadata: AppMetadata

    /// Cached compatibility result captured at import time (recomputed on demand).
    var compatibility: CompatibilityReport?

    /// Size of the stored IPA on disk.
    var ipaSizeBytes: Int64

    var displayVersion: String { "v\(version) build \(buildNumber)" }
}

extension AppVersion {
    /// Best-effort numeric comparison of build numbers for ordering/"is newer".
    var buildNumberValue: Int? { Int(buildNumber.split(separator: ".").first.map(String.init) ?? buildNumber) }

    /// Compare two builds of the same bundle id. Returns true if `self` is a
    /// strictly newer build than `other` (version first, then build number).
    func isNewer(than other: AppVersion) -> Bool {
        if version != other.version {
            return AppVersion.compareVersionStrings(version, other.version) == .orderedDescending
        }
        if let a = buildNumberValue, let b = other.buildNumberValue, a != b {
            return a > b
        }
        return importDate > other.importDate
    }

    /// Compare dotted version strings like "1.0.3" vs "1.1".
    static func compareVersionStrings(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let l = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let r = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(l.count, r.count)
        for i in 0..<count {
            let a = i < l.count ? l[i] : 0
            let b = i < r.count ? r[i] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
