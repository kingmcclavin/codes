#if canImport(UIKit)
import Foundation
import UIKit

/// Customisations applied to the exported app.
struct IPAExportOptions {
    /// Home-screen name (CFBundleDisplayName / CFBundleName). nil keeps the current name.
    var displayName: String?
    /// New app icon. nil keeps the current icon.
    var icon: UIImage?
    /// Bundle identifier. nil uses the current one without "swift-playgrounds-".
    var bundleIdentifier: String?
}

enum IPAExportError: LocalizedError {
    case unreadableInfoPlist
    case iconRenderingFailed

    var errorDescription: String? {
        switch self {
        case .unreadableInfoPlist: return "The app's Info.plist could not be read."
        case .iconRenderingFailed: return "The icon image could not be converted."
        }
    }
}

/// Exports the running app as an .ipa (unsigned: sideloading tools such as
/// AltStore or SideStore re-sign it), then returns the path to the file.
/// Returns String because the app crashes when returning URL from an async
/// function in Swift Playgrounds.
func exportIPA(options: IPAExportOptions = IPAExportOptions()) async throws -> String {
    let fileManager = FileManager.default

    // Path to app bundle
    let bundleURL = Bundle.main.bundleURL

    // Create Payload/ directory
    let temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let payloadDirectory = temporaryDirectory.appendingPathComponent("Payload")
    try fileManager.createDirectory(at: payloadDirectory, withIntermediateDirectories: true, attributes: nil)

    defer {
        // Remove temporary directory
        try? fileManager.removeItem(at: temporaryDirectory)
    }

    let currentName = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String ?? "App"
    let appName = options.displayName.map(sanitizedDisplayName).flatMap { $0.isEmpty ? nil : $0 } ?? currentName
    let fileName = sanitizedFileName(appName)
    let appURL = payloadDirectory.appendingPathComponent("\(fileName).app")
    let ipaURL = fileManager.temporaryDirectory.appendingPathComponent("\(fileName).ipa")

    // Copy app bundle to Payload/
    try fileManager.copyItem(at: bundleURL, to: appURL)

    // Load Info.plist
    let plistURL = appURL.appendingPathComponent("Info.plist")
    guard let infoPlist = NSMutableDictionary(contentsOf: plistURL) else {
        throw IPAExportError.unreadableInfoPlist
    }

    // Bundle identifier: remove "swift-playgrounds-" (Apple forbids
    // registering App IDs containing that string), or use the custom one.
    let currentID = Bundle.main.bundleIdentifier ?? "com.example.app"
    let customID = options.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    infoPlist[kCFBundleIdentifierKey as String] = customID.isEmpty
        ? currentID.replacingOccurrences(of: "swift-playgrounds-", with: "")
        : customID

    // Name shown on the home screen
    if options.displayName != nil {
        infoPlist["CFBundleDisplayName"] = appName
        infoPlist[kCFBundleNameKey as String] = appName
    }

    // App icon
    if let icon = options.icon {
        try installIcon(icon, in: appURL, infoPlist: infoPlist)
    }

    try infoPlist.write(to: plistURL)

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        // Coordinating read access to Payload/ "forUploading" automatically zips the directory for us.
        let readIntent = NSFileAccessIntent.readingIntent(with: payloadDirectory, options: .forUploading)

        let fileCoordinator = NSFileCoordinator()
        fileCoordinator.coordinate(with: [readIntent], queue: .main) { error in
            do {
                if let error { throw error }

                // Change file extension from "zip" to "ipa"
                if fileManager.fileExists(atPath: ipaURL.path) {
                    try fileManager.removeItem(at: ipaURL)
                }
                try fileManager.copyItem(at: readIntent.url, to: ipaURL)

                print("Exported .ipa:", ipaURL)
                continuation.resume()
            } catch {
                print("Failed to export .ipa:", error)
                continuation.resume(throwing: error)
            }
        }
    }

    return ipaURL.path
}

// MARK: - Icon

/// Writes the icon as loose PNG files and points Info.plist at them.
///
/// Swift Playgrounds compiles its icon into Assets.car and references it via
/// CFBundleIconName; removing that key makes iOS use the CFBundleIconFiles
/// PNGs instead, so no asset-catalog compiler is needed.
private func installIcon(_ image: UIImage, in appURL: URL, infoPlist: NSMutableDictionary) throws {
    // (base name, point size, scales)
    let variants: [(name: String, points: CGFloat, scales: [CGFloat])] = [
        ("TI84Icon20x20", 20, [2, 3]),
        ("TI84Icon29x29", 29, [2, 3]),
        ("TI84Icon40x40", 40, [2, 3]),
        ("TI84Icon60x60", 60, [2, 3]),
        ("TI84Icon76x76", 76, [1, 2]),
        ("TI84Icon83.5x83.5", 83.5, [2]),
    ]

    for variant in variants {
        for scale in variant.scales {
            let suffix = scale == 1 ? "" : "@\(Int(scale))x"
            let pixels = variant.points * scale
            guard let png = renderIcon(image, pixelSize: pixels) else { throw IPAExportError.iconRenderingFailed }
            try png.write(to: appURL.appendingPathComponent("\(variant.name)\(suffix).png"))
            // iPad variants need the ~ipad file name too.
            try png.write(to: appURL.appendingPathComponent("\(variant.name)\(suffix)~ipad.png"))
        }
    }

    let phoneFiles = ["TI84Icon20x20", "TI84Icon29x29", "TI84Icon40x40", "TI84Icon60x60"]
    let padFiles = phoneFiles + ["TI84Icon76x76", "TI84Icon83.5x83.5"]

    infoPlist.removeObject(forKey: "CFBundleIconName")
    infoPlist["CFBundleIcons"] = ["CFBundlePrimaryIcon": ["CFBundleIconFiles": phoneFiles]]
    infoPlist["CFBundleIcons~ipad"] = ["CFBundlePrimaryIcon": ["CFBundleIconFiles": padFiles]]
}

/// Square, opaque PNG (iOS icons must not be transparent) with the image
/// scaled to fill and centred.
private func renderIcon(_ image: UIImage, pixelSize: CGFloat) -> Data? {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let size = CGSize(width: pixelSize, height: pixelSize)
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let rendered = renderer.image { context in
        UIColor.white.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        let aspect = max(size.width / image.size.width, size.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * aspect, height: image.size.height * aspect)
        let origin = CGPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)
        image.draw(in: CGRect(origin: origin, size: drawSize))
    }
    return rendered.pngData()
}

// MARK: - Names

private func sanitizedDisplayName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// File-system-safe version of the app name for the .app and .ipa files.
private func sanitizedFileName(_ name: String) -> String {
    let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
    let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
    return cleaned.isEmpty ? "App" : cleaned
}
#endif
