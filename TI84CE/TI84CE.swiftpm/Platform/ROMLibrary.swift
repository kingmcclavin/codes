import Foundation
#if canImport(EmulatorCore)
import EmulatorCore
#endif

/// Finds the TI-84 Plus CE ROM: either shipped inside the app as a package resource
/// (TI84CE.swiftpm/Resources/*.rom) or imported by the user through the Files
/// picker, in which case a private copy is kept in Application Support.
/// The ROM file itself is never modified.
public struct ROMLibrary {
    public enum Source: Equatable {
        case bundled(URL)
        case imported(URL)

        public var url: URL {
            switch self {
            case .bundled(let u), .imported(let u): return u
            }
        }

        public var label: String {
            switch self {
            case .bundled: return "App resource"
            case .imported: return "Imported"
            }
        }
    }

    /// Resource names tried first (with the .rom extension).
    public static let preferredNames = ["ti84ce", "ti84rom", "ti-84ce", "TI84CE", "TI-84 Plus CE", "rom"]

    public let storageDirectory: URL

    public init(storageDirectory: URL) {
        self.storageDirectory = storageDirectory
    }

    public var importedROMURL: URL { storageDirectory.appendingPathComponent("ROM/ti84ce.rom") }

    /// Imported ROM first (the user chose it explicitly), then a bundled one.
    public func locate(bundle: Bundle = .main) -> Source? {
        if FileManager.default.fileExists(atPath: importedROMURL.path) { return .imported(importedROMURL) }
        if let url = ROMLibrary.bundledROM(in: bundle) { return .bundled(url) }
        return nil
    }

    /// Searches the app bundle and any nested SwiftPM resource bundles.
    public static func bundledROM(in bundle: Bundle) -> URL? {
        var bundles = [bundle]
        if let resources = bundle.resourceURL,
           let items = try? FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil) {
            bundles += items.filter { $0.pathExtension == "bundle" }.compactMap { Bundle(url: $0) }
        }
        for b in bundles {
            for name in preferredNames {
                if let u = b.url(forResource: name, withExtension: "rom") { return u }
            }
        }
        // Any other *.rom file among the resources.
        for b in bundles {
            guard let dir = b.resourceURL,
                  let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            if let u = items.first(where: { $0.pathExtension.lowercased() == "rom" }) { return u }
        }
        return nil
    }

    /// Validates and copies a user-selected ROM into app storage.
    @discardableResult
    public func importROM(from source: URL) throws -> ROMImage {
        #if canImport(Darwin)
        // Files chosen with the document picker are security scoped.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        #endif
        let data = try Data(contentsOf: source)
        let rom = try ROMImage(data: [UInt8](data))
        try FileManager.default.createDirectory(at: importedROMURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: importedROMURL, options: .atomic)
        return rom
    }

    public func removeImportedROM() throws {
        if FileManager.default.fileExists(atPath: importedROMURL.path) {
            try FileManager.default.removeItem(at: importedROMURL)
        }
    }
}
