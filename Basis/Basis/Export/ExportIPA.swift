import Foundation
import UIKit

/// Options applied to the copied app bundle before it is zipped.
struct IPAExportOptions {
    /// Replaces the app icon (any size; it is center-cropped to a square).
    var icon: UIImage?
    /// Name shown under the icon on the Home Screen.
    var displayName: String?
}

// Export running app as .ipa, then return path to exported file.
// Returns String because app crashes when returning URL from async function for some reason...
func exportIPA(options: IPAExportOptions = IPAExportOptions()) async throws -> String
{
    // Path to app bundle
    let bundleURL = Bundle.main.bundleURL

    // Create Payload/ directory
    let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let payloadDirectory = temporaryDirectory.appendingPathComponent("Payload")
    try FileManager.default.createDirectory(at: payloadDirectory, withIntermediateDirectories: true, attributes: nil)

    defer {
        // Remove temporary directory
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let appName = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String ?? "App"
    let appURL = payloadDirectory.appendingPathComponent("\(appName).app")
    let ipaURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(appName).ipa")

    // Copy app bundle to Payload/
    try FileManager.default.copyItem(at: bundleURL, to: appURL)

    // Remove occurrences of "swift-playgrounds-" from bundle identifier.
    // (Apple forbids registering App IDs containing that string)
    let bundleID = Bundle.main.bundleIdentifier!
    let updatedBundleID = bundleID.replacingOccurrences(of: "swift-playgrounds-", with: "")

    // Update bundle identifier
    let plistURL = appURL.appendingPathComponent("Info.plist")
    let infoPlist = try NSMutableDictionary(contentsOf: plistURL, error: ())
    infoPlist[kCFBundleIdentifierKey as String] = updatedBundleID

    if let name = options.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
        infoPlist["CFBundleDisplayName"] = name
    }
    if let icon = options.icon {
        try AppIconWriter.install(icon, inAppBundle: appURL, infoPlist: infoPlist)
    }
    try infoPlist.write(to: plistURL)

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        // Coordinating read access to Payload/ "forUploading" automatically zips the directory for us.
        let readIntent = NSFileAccessIntent.readingIntent(with: payloadDirectory, options: .forUploading)

        let fileCoordinator = NSFileCoordinator()
        fileCoordinator.coordinate(with: [readIntent], queue: .main) { error in
            do
            {
                guard error == nil else { throw error! }

                // Change file extension from "zip" to "ipa"
                _ = try FileManager.default.replaceItemAt(ipaURL, withItemAt: readIntent.url)

                print("Exported .ipa:", ipaURL)
                continuation.resume()
            }
            catch
            {
                print("Failed to export .ipa:", error)
                continuation.resume(throwing: error)
            }
        }
    }

    return ipaURL.path
}

/// Writes a custom icon into an app bundle as loose PNG files and points
/// Info.plist at them. The compiled asset catalog icon is bypassed by
/// removing `CFBundleIconName`, so iOS uses these files instead.
enum AppIconWriter {
    private static let baseNames = ["AppIcon60x60", "AppIcon76x76", "AppIcon83.5x83.5"]

    /// (file name, pixel size)
    private static let files: [(String, CGFloat)] = [
        ("AppIcon60x60@2x.png", 120),
        ("AppIcon60x60@3x.png", 180),
        ("AppIcon76x76@2x.png", 152),
        ("AppIcon76x76@2x~ipad.png", 152),
        ("AppIcon83.5x83.5@2x.png", 167),
        ("AppIcon83.5x83.5@2x~ipad.png", 167),
    ]

    static func install(_ image: UIImage, inAppBundle appURL: URL, infoPlist: NSMutableDictionary) throws {
        let square = squareOpaque(image, pixels: 1024)
        for (name, size) in files {
            guard let data = resized(square, pixels: size).pngData() else { continue }
            try data.write(to: appURL.appendingPathComponent(name), options: .atomic)
        }
        let primary: [String: Any] = ["CFBundleIconFiles": baseNames]
        infoPlist["CFBundleIcons"] = ["CFBundlePrimaryIcon": primary]
        infoPlist["CFBundleIcons~ipad"] = ["CFBundlePrimaryIcon": primary]
        infoPlist.removeObject(forKey: "CFBundleIconName")
    }

    /// Center-crops to a square and flattens onto white (iOS icons must be opaque).
    static func squareOpaque(_ image: UIImage, pixels: CGFloat) -> UIImage {
        let side = min(image.size.width, image.size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: pixels, height: pixels), format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
            let scale = pixels / max(side, 1)
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (pixels - drawSize.width) / 2, y: (pixels - drawSize.height) / 2,
                                  width: drawSize.width, height: drawSize.height))
        }
    }

    private static func resized(_ image: UIImage, pixels: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: pixels, height: pixels), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        }
    }
}
