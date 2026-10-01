import Foundation

/// Static inspection of an `.ipa`: locates the `.app` bundle inside `Payload/`,
/// reads `Info.plist`, the Mach-O header, `PlugIns/` extensions, and best-effort
/// entitlements from `embedded.mobileprovision`.
struct ParsedIPA {
    let metadata: AppMetadata
    /// e.g. "Payload/Calculator.app/" — prefix of every path inside the bundle.
    let appBundlePrefix: String
    /// Path inside the zip of the best icon candidate, if one was found.
    let iconEntryPath: String?
    /// Retained so callers (icon extraction) can pull more entries without re-reading.
    let zip: MiniZip
}

enum IPAParser {

    enum ParseError: LocalizedError {
        case noPayload
        case noAppBundle
        case noInfoPlist
        case badInfoPlist(String)

        var errorDescription: String? {
            switch self {
            case .noPayload:   return "The IPA has no Payload/ directory."
            case .noAppBundle: return "No .app bundle was found inside Payload/."
            case .noInfoPlist: return "The app bundle has no Info.plist."
            case .badInfoPlist(let w): return "Info.plist could not be read: \(w)"
            }
        }
    }

    static func parse(ipaURL: URL) throws -> ParsedIPA {
        let zip = try MiniZip(url: ipaURL)

        // Find the .app bundle: the shortest path matching "Payload/*.app/".
        guard zip.entries.contains(where: { $0.path.hasPrefix("Payload/") }) else {
            throw ParseError.noPayload
        }
        guard let appPrefix = appBundlePrefix(in: zip) else {
            throw ParseError.noAppBundle
        }

        // Read Info.plist.
        guard let plistData = try zip.extractData(atPath: appPrefix + "Info.plist") else {
            throw ParseError.noInfoPlist
        }
        let info: [String: Any]
        do {
            guard let dict = try PropertyListSerialization.propertyList(
                from: plistData, options: [], format: nil) as? [String: Any] else {
                throw ParseError.badInfoPlist("root is not a dictionary")
            }
            info = dict
        } catch {
            throw ParseError.badInfoPlist(error.localizedDescription)
        }

        // Core string fields.
        let displayName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? deriveName(fromPrefix: appPrefix)
        let bundleID = (info["CFBundleIdentifier"] as? String) ?? "unknown.bundle.id"
        let version = (info["CFBundleShortVersionString"] as? String) ?? "0"
        let build = (info["CFBundleVersion"] as? String) ?? "0"
        let minOS = (info["MinimumOSVersion"] as? String) ?? "0"
        let exeName = info["CFBundleExecutable"] as? String

        // Device families.
        var families: [AppMetadata.DeviceFamily] = []
        if let nums = info["UIDeviceFamily"] as? [NSNumber] {
            families = nums.compactMap { AppMetadata.DeviceFamily(rawValue: $0.intValue) }
        }

        // Bundle size = sum of uncompressed sizes of everything under the prefix.
        let bundleSize = zip.entries(withPrefix: appPrefix)
            .reduce(Int64(0)) { $0 + Int64($1.uncompressedSize) }

        // Mach-O architectures (best effort).
        var archs: [String] = []
        if let exeName, let exeData = try? zip.extractData(atPath: appPrefix + exeName) {
            archs = MachO.architectures(in: exeData)
        }

        // App extensions under PlugIns/.
        let plugInsPrefix = appPrefix + "PlugIns/"
        let extensionNames = Set(
            zip.entries(withPrefix: plugInsPrefix)
               .compactMap { entry -> String? in
                   let rest = entry.path.dropFirst(plugInsPrefix.count)
                   guard let first = rest.split(separator: "/").first else { return nil }
                   return first.hasSuffix(".appex") ? String(first) : nil
               }
        ).sorted()

        // Entitlements from embedded.mobileprovision (best effort).
        let entitlementKeys = readEntitlementKeys(zip: zip, appPrefix: appPrefix)

        // Icon candidate.
        let iconPath = IconExtractor.bestIconEntryPath(info: info, zip: zip, appPrefix: appPrefix)

        let metadata = AppMetadata(
            displayName: displayName,
            bundleIdentifier: bundleID,
            version: version,
            buildNumber: build,
            minimumOSVersion: minOS,
            supportedDeviceFamilies: families,
            executableName: exeName,
            bundleSizeBytes: bundleSize,
            primaryIconFileName: iconPath.map { ($0 as NSString).lastPathComponent },
            architectures: archs,
            appExtensions: extensionNames,
            entitlementKeys: entitlementKeys)

        return ParsedIPA(metadata: metadata,
                         appBundlePrefix: appPrefix,
                         iconEntryPath: iconPath,
                         zip: zip)
    }

    // MARK: Helpers

    private static func appBundlePrefix(in zip: MiniZip) -> String? {
        // Look for any path "Payload/<Something>.app/..." and return the prefix.
        var candidate: String?
        for entry in zip.entries where entry.path.hasPrefix("Payload/") {
            let comps = entry.path.split(separator: "/", omittingEmptySubsequences: true)
            guard comps.count >= 2 else { continue }
            let second = String(comps[1])
            if second.hasSuffix(".app") {
                let prefix = "Payload/\(second)/"
                // Prefer the shortest / first found.
                if candidate == nil { candidate = prefix }
            }
        }
        return candidate
    }

    private static func deriveName(fromPrefix prefix: String) -> String {
        // "Payload/Calculator.app/" -> "Calculator"
        let comps = prefix.split(separator: "/")
        guard let appComp = comps.last else { return "App" }
        return String(appComp.replacingOccurrences(of: ".app", with: ""))
    }

    /// The provisioning profile embeds an XML plist with an `Entitlements` dict.
    /// We don't verify the signature (we're not a signing tool) — we only read
    /// the declared entitlement *keys* for the compatibility report.
    private static func readEntitlementKeys(zip: MiniZip, appPrefix: String) -> [String] {
        guard let data = try? zip.extractData(atPath: appPrefix + "embedded.mobileprovision"),
              let data, !data.isEmpty else { return [] }
        // Find the embedded XML plist inside the CMS blob.
        guard let xmlRange = Self.plistRange(in: data),
              let dict = try? PropertyListSerialization.propertyList(
                from: data.subdata(in: xmlRange), options: [], format: nil) as? [String: Any],
              let ent = dict["Entitlements"] as? [String: Any] else {
            return []
        }
        return ent.keys.sorted()
    }

    private static func plistRange(in data: Data) -> Range<Int>? {
        let open = Array("<?xml".utf8)
        let close = Array("</plist>".utf8)
        guard let start = data.searchFirstRange(of: open),
              let end = data.searchLastRange(of: close) else { return nil }
        return start.lowerBound..<end.upperBound
    }
}

// MARK: - Small Data search helpers

private extension Data {
    func searchFirstRange(of pattern: [UInt8]) -> Range<Int>? {
        guard !pattern.isEmpty, count >= pattern.count else { return nil }
        for i in 0...(count - pattern.count) {
            var match = true
            for j in 0..<pattern.count where self[i + j] != pattern[j] { match = false; break }
            if match { return i..<(i + pattern.count) }
        }
        return nil
    }
    func searchLastRange(of pattern: [UInt8]) -> Range<Int>? {
        guard !pattern.isEmpty, count >= pattern.count else { return nil }
        var i = count - pattern.count
        while i >= 0 {
            var match = true
            for j in 0..<pattern.count where self[i + j] != pattern[j] { match = false; break }
            if match { return i..<(i + pattern.count) }
            i -= 1
        }
        return nil
    }
}
