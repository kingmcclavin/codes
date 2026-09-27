import UIKit
import UniformTypeIdentifiers

/// Copies elements through the system pasteboard. Vector data travels in a
/// private type (with embedded image assets, so pasting into another document
/// works); a rendered PNG is included for other apps.
@MainActor
enum Clipboard {
    static let typeIdentifier = "com.inkpad.elements"

    private struct Payload: Codable {
        var elements: [CanvasElement]
        var assets: [String: Data]
    }

    static var hasContent: Bool {
        UIPasteboard.general.contains(pasteboardTypes: [typeIdentifier]) || UIPasteboard.general.hasImages
    }

    static func copy(_ elements: [CanvasElement], assetsURL: URL, renderer: PageRenderer, background: PageBackground) {
        guard !elements.isEmpty else { return }
        var assets: [String: Data] = [:]
        for case let .image(img) in elements {
            if let data = try? Data(contentsOf: assetsURL.appendingPathComponent(img.assetName)) {
                assets[img.assetName] = data
            }
        }
        guard let data = try? JSONEncoder().encode(Payload(elements: elements, assets: assets)) else { return }
        var item: [String: Any] = [typeIdentifier: data]
        if let png = renderPNG(elements, renderer: renderer, background: background) {
            item[UTType.png.identifier] = png
        }
        UIPasteboard.general.setItems([item])
    }

    /// Returns pasted elements with fresh ids; image assets are written into
    /// `assetsURL`. Plain images from other apps become image elements.
    static func paste(into assetsURL: URL) -> [CanvasElement]? {
        let pb = UIPasteboard.general
        if let data = pb.data(forPasteboardType: typeIdentifier),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            try? FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
            for (name, bytes) in payload.assets {
                let url = assetsURL.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: url.path) { try? bytes.write(to: url, options: .atomic) }
            }
            return payload.elements.map { $0.withNewID() }
        }
        if let image = pb.image, let stored = ImageImporter.store(image, in: assetsURL) {
            return [.image(ImageElement(assetName: stored.name, box: BoxGeometry(center: .zero, size: stored.size)))]
        }
        return nil
    }

    private static func renderPNG(_ elements: [CanvasElement], renderer: PageRenderer, background: PageBackground) -> Data? {
        let bounds = elements.reduce(CGRect.null) { $0.union($1.bounds) }.expanded(by: 4)
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(3, 4096 / max(bounds.width, bounds.height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { ctx in
            ctx.cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
            for e in elements { renderer.draw(e, stamp: nil, in: ctx.cgContext, background: background) }
        }
        return image.pngData()
    }
}

/// Stores imported images as document assets.
enum ImageImporter {
    /// Downscales very large images, writes them to `assetsURL` and returns
    /// the asset name and a sensible display size in points.
    static func store(_ image: UIImage, in assetsURL: URL, maxPixels: CGFloat = 2600) -> (name: String, size: CGSize)? {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }
        let factor = min(1, maxPixels / max(pixelSize.width, pixelSize.height))
        let target = CGSize(width: floor(pixelSize.width * factor), height: floor(pixelSize.height * factor))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let hasAlpha: Bool = {
            guard let alpha = image.cgImage?.alphaInfo else { return false }
            return ![.none, .noneSkipFirst, .noneSkipLast].contains(alpha)
        }()
        format.opaque = !hasAlpha
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        let name = UUID().uuidString + (hasAlpha ? ".png" : ".jpg")
        guard let data = hasAlpha ? resized.pngData() : resized.jpegData(compressionQuality: 0.9) else { return nil }
        do {
            try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
            try data.write(to: assetsURL.appendingPathComponent(name), options: .atomic)
        } catch {
            return nil
        }
        // Display at 1 pt per 2 px (Retina), capped later by the caller.
        return (name, CGSize(width: target.width / 2, height: target.height / 2))
    }
}
