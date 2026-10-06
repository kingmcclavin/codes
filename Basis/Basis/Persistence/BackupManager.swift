import Foundation
import UIKit

/// A whole notebook in one file (`Title.basis`): the manifest, every page
/// with all its ink as vectors, and the images/PDFs it uses. Restoring one
/// gives back a fully editable notebook — old strokes can still be erased.
struct NotebookArchive: Codable {
    static let currentVersion = 1

    var archiveVersion = NotebookArchive.currentVersion
    var manifest: DocumentManifest
    var pages: [PageData]
    /// Asset file name → contents.
    var assets: [String: Data]
}

/// Creates and restores backups of the notebook library.
///
/// A backup is a folder that mirrors the library: every library folder is a
/// real folder, every notebook a file inside it — either an editable
/// `.basis` archive or a `.pdf`. Editable backups also include the
/// calculator data (formulas, variables, tables, history).
enum BackupManager {
    enum Format: String, CaseIterable, Identifiable {
        case editable, pdf
        var id: String { rawValue }
        var title: String { self == .editable ? "Editable (.basis)" : "PDF" }
        var fileExtension: String { self == .editable ? DocumentStore.packageExtension : "pdf" }
    }

    static let calculatorFileName = "Calculator Data.json"

    struct Report {
        var notebooks = 0
        var folders = 0
        var skipped = 0
        var failed: [String] = []
        var calculatorMessage: String?

        var summary: String {
            var parts: [String] = []
            parts.append("\(notebooks) notebook\(notebooks == 1 ? "" : "s")")
            if folders > 0 { parts.append("\(folders) folder\(folders == 1 ? "" : "s")") }
            var s = parts.joined(separator: " in ")
            if skipped > 0 { s += ", \(skipped) already in your library" }
            if !failed.isEmpty { s += ". Couldn't read: \(failed.joined(separator: ", "))" }
            if let calculatorMessage { s += ". \(calculatorMessage)" }
            return s
        }
    }

    // MARK: Reading notebooks

    /// Everything stored for one notebook package.
    static func archive(ofPackage pkg: URL) throws -> NotebookArchive {
        let decoder = DocumentStore.decoder()
        guard let data = try? Data(contentsOf: DocumentStore.manifestURL(pkg)) else { throw DocumentStoreError.missingManifest }
        let manifest = try decoder.decode(DocumentManifest.self, from: data)
        var pages: [PageData] = []
        for pid in manifest.pageIDs {
            if let d = try? Data(contentsOf: DocumentStore.pageURL(pkg, pid)), let p = try? decoder.decode(PageData.self, from: d) {
                pages.append(p)
            }
        }
        var assets: [String: Data] = [:]
        let assetsDir = DocumentStore.assetsURL(pkg)
        for f in (try? FileManager.default.contentsOfDirectory(at: assetsDir, includingPropertiesForKeys: nil)) ?? [] {
            if let d = try? Data(contentsOf: f) { assets[f.lastPathComponent] = d }
        }
        return NotebookArchive(manifest: manifest, pages: pages, assets: assets)
    }

    // MARK: Backup

    /// Library layout captured on the main thread, used off it.
    struct LibrarySnapshot {
        var root: URL
        var folders: [Folder]
        var documents: [(id: UUID, title: String, folderID: UUID?)]
    }

    @MainActor
    static func snapshot(of store: DocumentStore) -> LibrarySnapshot {
        LibrarySnapshot(root: store.rootURL, folders: store.folders,
                        documents: store.summaries.map { ($0.id, $0.title, $0.folderID) })
    }

    /// Writes a backup folder and returns its URL. Safe off the main thread.
    static func createBackup(_ library: LibrarySnapshot, format: Format, calculatorData: Data?,
                             in directory: URL = FileManager.default.temporaryDirectory) throws -> (url: URL, report: Report) {
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let backup = directory.appendingPathComponent("Basis Backup \(formatter.string(from: Date()))\(format == .pdf ? " (PDF)" : "")",
                                                       isDirectory: true)
        try? fm.removeItem(at: backup)
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)

        var report = Report()
        // Folder tree → directories.
        var folderURLs: [UUID: URL] = [:]
        func url(for folderID: UUID?) -> URL {
            guard let id = folderID, let folder = library.folders.first(where: { $0.id == id }) else { return backup }
            if let u = folderURLs[id] { return u }
            let parent = url(for: folder.parentID)
            let u = uniqueURL(in: parent, name: safeName(folder.name), ext: nil)
            try? fm.createDirectory(at: u, withIntermediateDirectories: true)
            folderURLs[id] = u
            return u
        }
        for f in library.folders { _ = url(for: f.id) }
        report.folders = folderURLs.count

        let encoder = DocumentStore.encoder()
        for doc in library.documents {
            let pkg = library.root.appendingPathComponent("\(doc.id.uuidString).\(DocumentStore.packageExtension)", isDirectory: true)
            let title = doc.title.isEmpty ? "Untitled" : doc.title
            do {
                let archive = try archive(ofPackage: pkg)
                let target = uniqueURL(in: url(for: doc.folderID), name: safeName(title), ext: format.fileExtension)
                switch format {
                case .editable:
                    try encoder.encode(archive).write(to: target, options: .atomic)
                case .pdf:
                    try renderPDF(archive, assetsURL: DocumentStore.assetsURL(pkg), to: target)
                }
                report.notebooks += 1
            } catch {
                report.failed.append(title)
            }
        }
        if format == .editable, let calculatorData {
            try calculatorData.write(to: backup.appendingPathComponent(calculatorFileName), options: .atomic)
            report.calculatorMessage = "Calculator data included."
        }
        return (backup, report)
    }

    static func renderPDF(_ archive: NotebookArchive, assetsURL: URL, to url: URL) throws {
        guard let first = archive.pages.first else { throw DocumentStoreError.missingManifest }
        let renderer = PageRenderer(assetsURL: assetsURL)
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: first.size))
        try pdf.writePDF(to: url) { ctx in
            for page in archive.pages {
                ctx.beginPage(withBounds: CGRect(origin: .zero, size: page.size), pageInfo: [:])
                renderer.drawPage(page, in: ctx.cgContext)
            }
        }
    }

    /// File names can't contain "/" or ":" and shouldn't start with ".".
    static func safeName(_ name: String) -> String {
        var s = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix(".") { s.removeFirst() }
        return s.isEmpty ? "Untitled" : String(s.prefix(120))
    }

    /// `Name.ext`, or `Name 2.ext` … if that exists already.
    static func uniqueURL(in dir: URL, name: String, ext: String?) -> URL {
        func make(_ n: String) -> URL {
            let u = dir.appendingPathComponent(n, isDirectory: ext == nil)
            return ext.map { u.appendingPathExtension($0) } ?? u
        }
        var candidate = make(name)
        var i = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = make("\(name) \(i)")
            i += 1
        }
        return candidate
    }

    // MARK: Restore

    /// Restores notebooks from backup folders and/or `.basis` files.
    /// Folders become library folders (merged by name); notebooks already in
    /// the library are skipped. Also accepts raw notebook packages and the
    /// "Basis Documents" folder itself.
    @MainActor
    static func restore(from urls: [URL], into store: DocumentStore, calculator: CalculatorStore?) -> Report {
        var report = Report()
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            restoreItem(url, parentFolder: nil, store: store, calculator: calculator, report: &report, isTopLevel: true)
        }
        store.reload()
        return report
    }

    @MainActor
    private static func restoreItem(_ url: URL, parentFolder: UUID?, store: DocumentStore, calculator: CalculatorStore?,
                                    report: inout Report, isTopLevel: Bool) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        let ext = url.pathExtension.lowercased()

        if isDir.boolValue {
            // A notebook package (from Basis Documents or an old InkPad folder).
            if fm.fileExists(atPath: DocumentStore.manifestURL(url).path) {
                restorePackage(url, folderID: parentFolder, store: store, report: &report)
                return
            }
            // A plain folder: the backup itself stays top level, other folders
            // become library folders.
            var folderID = parentFolder
            let name = url.lastPathComponent
            let isContainer = name.hasPrefix("Basis Backup") || name == "Basis Documents" || name == "InkPad Documents"
            if !(isTopLevel && isContainer) {
                if let existing = store.subfolders(of: parentFolder).first(where: { $0.name == name }) {
                    folderID = existing.id
                } else {
                    folderID = store.createFolder(name: name, in: parentFolder).id
                    report.folders += 1
                }
            }
            let items = ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            for item in items where !item.lastPathComponent.hasPrefix(".") {
                restoreItem(item, parentFolder: folderID, store: store, calculator: calculator, report: &report, isTopLevel: false)
            }
            return
        }

        if ext == DocumentStore.packageExtension || ext == "inkpad" {
            do {
                let data = try Data(contentsOf: url)
                let archive = try DocumentStore.decoder().decode(NotebookArchive.self, from: data)
                try install(archive, folderID: parentFolder, store: store, report: &report)
            } catch {
                report.failed.append(url.deletingPathExtension().lastPathComponent)
            }
        } else if ext == "goodnotes" {
            do {
                try install(GoodNotesImporter.importFile(at: url).archive, folderID: parentFolder, store: store, report: &report)
            } catch {
                report.failed.append(url.deletingPathExtension().lastPathComponent)
            }
        } else if url.lastPathComponent == calculatorFileName, let calculator, let data = try? Data(contentsOf: url) {
            report.calculatorMessage = try? calculator.importData(data)
        }
    }

    @MainActor
    private static func restorePackage(_ pkg: URL, folderID: UUID?, store: DocumentStore, report: inout Report) {
        do {
            try install(archive(ofPackage: pkg), folderID: folderID, store: store, report: &report)
        } catch {
            report.failed.append(pkg.deletingPathExtension().lastPathComponent)
        }
    }

    /// Writes an archive into the library as a new notebook package.
    @MainActor
    static func install(_ archive: NotebookArchive, folderID: UUID?, store: DocumentStore, report: inout Report) throws {
        guard archive.archiveVersion <= NotebookArchive.currentVersion,
              archive.manifest.formatVersion <= DocumentManifest.currentFormatVersion else {
            throw DocumentStoreError.unsupportedVersion(archive.manifest.formatVersion)
        }
        if store.exists(archive.manifest.id) {
            report.skipped += 1
            return
        }
        var manifest = archive.manifest
        manifest.folderID = folderID
        // Keep only pages that exist; a notebook always has at least one.
        var pages = archive.pages
        if pages.isEmpty { pages = [PageData(size: manifest.firstPageSize, background: PageBackground())] }
        manifest.pageIDs = pages.map(\.id)
        let pkg = store.packageURL(manifest.id)
        try DocumentStore.write(DocumentModel.Snapshot(manifest: manifest, dirtyPages: pages, livePageIDs: Set(manifest.pageIDs)), to: pkg)
        let assets = DocumentStore.assetsURL(pkg)
        for (name, data) in archive.assets where !name.contains("/") {
            try data.write(to: assets.appendingPathComponent(name), options: .atomic)
        }
        report.notebooks += 1
    }
}
