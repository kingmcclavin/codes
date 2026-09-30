import Foundation
import SwiftUI
import UIKit

/// App-wide preferences: custom pen presets, recent colors, last document.
/// Used from the main thread only.
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    @Published var customPresets: [PenPreset] { didSet { save(customPresets, key: Keys.presets) } }
    @Published private(set) var recentColors: [RGBAColor] { didSet { save(recentColors, key: Keys.recent) } }
    /// App-wide accent color (nil = system blue).
    @Published var accentColor: RGBAColor? { didSet { save(accentColor, key: Keys.accent) } }
    @Published var lastOpenedDocumentID: UUID? {
        didSet { UserDefaults.standard.set(lastOpenedDocumentID?.uuidString, forKey: Keys.lastDocument) }
    }

    private enum Keys {
        static let presets = "customPenPresets"
        static let recent = "recentColors"
        static let lastDocument = "lastOpenedDocument"
        static let accent = "accentColor"
    }

    private init() {
        customPresets = Self.load([PenPreset].self, key: Keys.presets) ?? []
        recentColors = Self.load([RGBAColor].self, key: Keys.recent) ?? []
        accentColor = Self.load(RGBAColor?.self, key: Keys.accent) ?? nil
        lastOpenedDocumentID = UserDefaults.standard.string(forKey: Keys.lastDocument).flatMap(UUID.init(uuidString:))
    }

    func noteColorUsed(_ c: RGBAColor) {
        let opaque = c.withAlpha(1)
        if RGBAColor.inkPalette.contains(where: { $0.isClose(to: opaque) })
            || RGBAColor.highlighterPalette.contains(where: { $0.isClose(to: opaque) }) { return }
        var list = recentColors.filter { !$0.isClose(to: opaque) }
        // The system color picker reports every intermediate color while the
        // user drags; treat a quick succession as one choice.
        let now = Date()
        if now.timeIntervalSince(lastColorNote) < 1.5, !list.isEmpty, recentColors.first.map({ !$0.isClose(to: opaque) }) ?? false {
            list.removeFirst()
        }
        lastColorNote = now
        list.insert(opaque, at: 0)
        recentColors = Array(list.prefix(8))
    }

    private var lastColorNote = Date.distantPast

    func savePreset(name: String, style: StrokeStyle) {
        customPresets.append(PenPreset(id: UUID(), name: name, style: style, isBuiltIn: false))
    }

    func deletePreset(_ id: UUID) {
        customPresets.removeAll { $0.id == id }
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

extension UIColor {
    /// The user's accent color, for UIKit drawing (selection, lasso, etc.).
    static var appAccent: UIColor { AppPreferences.shared.accentColor?.uiColor ?? .systemBlue }
}

extension Color {
    /// The user's accent color for SwiftUI views that are rebuilt when shown
    /// (editor chrome, sheets). Library views use `.tint`, set at the root.
    static var appAccent: Color { AppPreferences.shared.accentColor?.color ?? .accentColor }
}
