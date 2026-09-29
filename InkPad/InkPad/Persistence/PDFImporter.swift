import CoreGraphics
import Foundation

enum PDFImportError: LocalizedError {
    case unreadable
    case locked
    case empty

    var errorDescription: String? {
        switch self {
        case .unreadable: return "The PDF couldn't be opened."
        case .locked: return "The PDF is password protected."
        case .empty: return "The PDF has no pages."
        }
    }
}

/// Turns a PDF into notebook pages. The PDF is copied into the document's
/// assets and each page becomes a page whose background is that PDF page, so
/// it stays vector-sharp and can be written on like any other page.
enum PDFImporter {
    /// - Parameters:
    ///   - url: the PDF to import (security-scoped access is handled here)
    ///   - assetsURL: the target document's assets folder
    static func pages(from url: URL, into assetsURL: URL) throws -> [PageData] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let doc = CGPDFDocument(url as CFURL) else { throw PDFImportError.unreadable }
        if doc.isEncrypted && !doc.isUnlocked && !doc.unlockWithPassword("") { throw PDFImportError.locked }
        guard doc.numberOfPages > 0 else { throw PDFImportError.empty }

        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        let assetName = UUID().uuidString + ".pdf"
        try FileManager.default.copyItem(at: url, to: assetsURL.appendingPathComponent(assetName))

        return (1...doc.numberOfPages).compactMap { number in
            guard let page = doc.page(at: number) else { return nil }
            return PageData(size: displaySize(of: page),
                            background: PageBackground(color: .white, template: .blank,
                                                       pdf: PDFPageSource(assetName: assetName, pageIndex: number - 1)))
        }
    }

    /// Page size in points as displayed (crop box, honouring page rotation).
    static func displaySize(of page: CGPDFPage) -> CGSize {
        let box = page.getBoxRect(.cropBox)
        let rotated = abs(page.rotationAngle) % 180 == 90
        let size = rotated ? CGSize(width: box.height, height: box.width) : box.size
        return CGSize(width: max(size.width, 36).rounded(), height: max(size.height, 36).rounded())
    }

    /// File name without extension, used as the notebook title.
    static func title(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? "Imported PDF" : name
    }
}
