import Foundation
import UIKit

/// Produces a static `CompatibilityReport` for a parsed IPA, plus an honest
/// statement about whether the current runtime can actually launch it.
enum CompatibilityChecker {

    /// Entitlements that a normal sandboxed, non-jailbroken container cannot
    /// honor for a *guest* executable. Their presence doesn't block import,
    /// but we flag them.
    private static let sensitiveEntitlements: Set<String> = [
        "com.apple.developer.kernel.increased-memory-limit",
        "dynamic-codesigning",
        "com.apple.private.security.no-sandbox",
        "com.apple.developer.associated-domains",
        "keychain-access-groups",
        "com.apple.developer.networking.networkextension",
        "com.apple.developer.healthkit",
        "com.apple.developer.homekit"
    ]

    static func evaluate(_ parsed: ParsedIPA) -> CompatibilityReport {
        var checks: [CompatibilityReport.Check] = []
        let meta = parsed.metadata

        checks.append(.init(status: .pass, title: "Valid IPA", detail: nil))
        checks.append(.init(status: .pass,
                            title: "Application bundle found",
                            detail: parsed.appBundlePrefix))

        // Architecture.
        if meta.architectures.contains("arm64") {
            checks.append(.init(status: .pass, title: "Supported architecture (arm64)",
                                detail: meta.architectures.joined(separator: ", ")))
        } else if meta.architectures.isEmpty {
            checks.append(.init(status: .warn, title: "Architecture unknown",
                                detail: "Could not read the Mach-O header."))
        } else {
            checks.append(.init(status: .warn, title: "No arm64 slice",
                                detail: meta.architectures.joined(separator: ", ")))
        }

        // OS version.
        let current = UIDevice.current.systemVersion
        if versionLessOrEqual(meta.minimumOSVersion, current) || meta.minimumOSVersion == "0" {
            checks.append(.init(status: .pass,
                                title: "Compatible OS version",
                                detail: "Requires iOS \(meta.minimumOSVersion); device is \(current)."))
        } else {
            checks.append(.init(status: .fail,
                                title: "Requires newer iOS",
                                detail: "Requires iOS \(meta.minimumOSVersion); device is \(current)."))
        }

        // Entitlements.
        let flagged = meta.entitlementKeys.filter { sensitiveEntitlements.contains($0) }
        if meta.entitlementKeys.isEmpty {
            checks.append(.init(status: .info, title: "Entitlements not readable",
                                detail: "No embedded provisioning profile found to inspect."))
        } else if flagged.isEmpty {
            checks.append(.init(status: .pass, title: "Basic entitlements", detail: nil))
        } else {
            checks.append(.init(status: .warn,
                                title: "Uses restricted entitlement(s)",
                                detail: flagged.joined(separator: ", ")))
        }

        // Extensions.
        if meta.appExtensions.isEmpty {
            checks.append(.init(status: .pass, title: "No app extensions detected", detail: nil))
        } else {
            checks.append(.init(status: .warn,
                                title: "Contains app extension(s)",
                                detail: meta.appExtensions.joined(separator: ", ")))
        }

        // Determine static level.
        let hasFail = checks.contains { $0.status == .fail }
        let hasWarn = checks.contains { $0.status == .warn }
        let level: CompatibilityReport.Level = hasFail ? .unsupported : (hasWarn ? .limited : .good)

        // Honest runtime verdict (see RuntimeManager / README). Built directly
        // (not via the MainActor singleton) so this can run off the main thread
        // during import.
        let (launchable, explanation) = InspectionRuntime().canLaunch(meta)

        return CompatibilityReport(level: level,
                                   checks: checks,
                                   runtimeLaunchable: launchable,
                                   runtimeExplanation: explanation)
    }

    private static func versionLessOrEqual(_ a: String, _ b: String) -> Bool {
        AppVersion.compareVersionStrings(a, b) != .orderedDescending
    }
}
