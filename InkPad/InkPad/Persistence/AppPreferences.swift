import Foundation
import SwiftUI

/// App-wide preferences: custom pen presets, recent colors, last document.
/// Used from the main thread only.
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    @Published var customPresets: [PenPreset] { didSet { save(customPresets, key: Keys.presets) } }
    @Published private(set) var recentColors: [RGBAColor] { didSet { save(recentColors, key: Keys.recent) } }
    @Published var lastOpenedDocumentID: UUID? {
        didSet { UserDefaults.standard.set(lastOpenedDocumentID?.uuidString, forKey: Keys.lastDocument) }
    }

    private enum Keys {
        static let presets = "customPenPresets"
        static let recent = "recentColors"
        static let lastDocument = "lastOpenedDocument"
    }

    private init() {
        customPresets = Self.load([PenPreset].self, key: Keys.presets) ?? []
        recentColors = Self.load([RGBAColor].self, key: Keys.recent) ?? []
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
