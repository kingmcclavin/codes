import Foundation

/// Raw-ish metadata read out of an IPA's `Info.plist` plus a few derived values.
/// This is produced by `IPAParser` and consumed by the library, details screen,
/// and the compatibility checker.
struct AppMetadata: Codable, Hashable {
    var displayName: String
    var bundleIdentifier: String
    var version: String          // CFBundleShortVersionString
    var buildNumber: String      // CFBundleVersion
    var minimumOSVersion: String // MinimumOSVersion
    var supportedDeviceFamilies: [DeviceFamily]
    var executableName: String?  // CFBundleExecutable
    var bundleSizeBytes: Int64   // size of the whole .app payload
    var primaryIconFileName: String?

    /// Architectures found in the Mach-O executable (best-effort).
    var architectures: [String]

    /// Names of app extensions found under `PlugIns/`.
    var appExtensions: [String]

    /// Entitlement keys we could recover from the embedded code signature
    /// (best-effort — see `IPAParser`).
    var entitlementKeys: [String]

    enum DeviceFamily: Int, Codable, Hashable, CaseIterable {
        case iPhone = 1
        case iPad = 2
        case tv = 3
        case watch = 4
        case mac = 6

        var displayName: String {
            switch self {
            case .iPhone: return "iPhone"
            case .iPad:   return "iPad"
            case .tv:     return "Apple TV"
            case .watch:  return "Apple Watch"
            case .mac:    return "Mac"
            }
        }
    }

    static func empty(bundleIdentifier: String = "unknown",
                      displayName: String = "Unknown App") -> AppMetadata {
        AppMetadata(displayName: displayName,
                    bundleIdentifier: bundleIdentifier,
                    version: "0",
                    buildNumber: "0",
                    minimumOSVersion: "0",
                    supportedDeviceFamilies: [],
                    executableName: nil,
                    bundleSizeBytes: 0,
                    primaryIconFileName: nil,
                    architectures: [],
                    appExtensions: [],
                    entitlementKeys: [])
    }
}

extension AppMetadata {
    var versionLabel: String { "v\(version) (\(buildNumber))" }

    var deviceFamilyLabel: String {
        guard !supportedDeviceFamilies.isEmpty else { return "Unknown" }
        return supportedDeviceFamilies.map(\.displayName).joined(separator: ", ")
    }

    var formattedBundleSize: String {
        ByteCountFormatter.string(fromByteCount: bundleSizeBytes, countStyle: .file)
    }
}
