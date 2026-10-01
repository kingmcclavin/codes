import Foundation
import UIKit

/// Chooses and extracts the app icon from an IPA.
///
/// iOS app icons are frequently stored as "CgBI" / Apple-optimized PNGs, which
/// generic PNG decoders choke on. Because we run **on-device** (iPadOS),
/// `UIImage(data:)` can decode these natively, so icon extraction works without
/// any special un-crushing step.
enum IconExtractor {

    /// Determine the best icon entry path inside the zip from Info.plist, with a
    /// filename-pattern fallback.
    static func bestIconEntryPath(info: [String: Any], zip: MiniZip, appPrefix: String) -> String? {
        var candidateNames: [String] = []

        // CFBundleIcons -> CFBundlePrimaryIcon -> CFBundleIconFiles
        if let icons = info["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            candidateNames.append(contentsOf: files)
        }
        // iPad variant.
        if let icons = info["CFBundleIcons~ipad"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            candidateNames.append(contentsOf: files)
        }
        // Legacy keys.
        if let files = info["CFBundleIconFiles"] as? [String] {
            candidateNames.append(contentsOf: files)
        }
        if let name = info["CFBundleIconFile"] as? String {
            candidateNames.append(name)
        }

        // Base names in Info.plist omit resolution/extension suffixes
        // (e.g. "AppIcon" -> "AppIcon60x60@2x.png"). Match by prefix, pick the
        // entry whose name encodes the largest size.
        let allAppEntries = zip.entries(withPrefix: appPrefix)

        func score(_ path: String) -> Int {
            // crude: larger "NxN" and higher @Nx rank higher
            let name = (path as NSString).lastPathComponent.lowercased()
            var s = 0
            if let r = name.range(of: #"(\d+)x\d+"#, options: .regularExpression),
               let dim = Int(name[r].prefix(while: { $0.isNumber })) {
                s += dim * 10
            }
            if name.contains("@3x") { s += 3 }
            else if name.contains("@2x") { s += 2 }
            return s
        }

        var matches: [String] = []
        for base in candidateNames {
            let baseLower = base.lowercased()
            for entry in allAppEntries where !entry.isDirectory {
                let fileName = (entry.path as NSString).lastPathComponent.lowercased()
                if fileName.hasPrefix(baseLower) && fileName.hasSuffix(".png") {
                    matches.append(entry.path)
                }
            }
        }

        // Fallback: any top-level AppIcon*.png in the bundle.
        if matches.isEmpty {
            for entry in allAppEntries where !entry.isDirectory {
                let fileName = (entry.path as NSString).lastPathComponent.lowercased()
                if (fileName.contains("appicon") || fileName.hasPrefix("icon")),
                   fileName.hasSuffix(".png") {
                    matches.append(entry.path)
                }
            }
        }

        return matches.max { score($0) < score($1) }
    }

    /// Extract the icon bytes and re-encode as a standard PNG we can save and
    /// reload. Returns normalized PNG data, or nil if decoding failed.
    static func extractIconPNG(from parsed: ParsedIPA) -> Data? {
        guard let iconPath = parsed.iconEntryPath,
              let raw = try? parsed.zip.extractData(atPath: iconPath) else { return nil }
        // On-device UIImage can decode CgBI/optimized PNGs.
        guard let image = UIImage(data: raw) else { return raw } // fall back to raw bytes
        return image.pngData() ?? raw
    }
}
