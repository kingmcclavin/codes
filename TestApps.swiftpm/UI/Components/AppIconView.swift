import SwiftUI
import UIKit

/// Loads an app's extracted icon from disk (by relative path) with a graceful
/// placeholder. Caches decoded images in-memory to keep the Home Screen smooth.
struct AppIconView: View {
    let app: ContainerApp
    var size: CGFloat = 60
    var cornerRadius: CGFloat { size * 0.2237 } // iOS squircle ratio approximation

    var body: some View {
        Group {
            if let image = IconCache.shared.image(for: app.activeVersion) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [.blue, .purple],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var initials: String {
        let words = app.displayLabel.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}

/// Simple in-memory icon cache keyed by version id.
final class IconCache {
    static let shared = IconCache()
    private var cache: [UUID: UIImage] = [:]
    private let lock = NSLock()

    func image(for version: AppVersion) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[version.id] { return cached }
        guard let rel = version.iconRelativePath else { return nil }
        let url = ContainerStorage.shared.absoluteURL(forRelative: rel)
        guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else {
            return nil
        }
        cache[version.id] = img
        return img
    }

    func invalidate(_ versionID: UUID) {
        lock.lock(); cache[versionID] = nil; lock.unlock()
    }
}
