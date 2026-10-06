import CoreGraphics
import Foundation
import ImageIO

/// Caches expensive per-element geometry (stroke outlines). Thread safe.
final class RenderCache: @unchecked Sendable {
    static let shared = RenderCache()

    private final class PathBox {
        let path: CGPath
        init(_ path: CGPath) { self.path = path }
    }

    private let paths = NSCache<NSString, PathBox>()

    private init() {
        paths.countLimit = 30_000
    }

    func strokePath(for stroke: Stroke, stamp: UInt64?) -> CGPath {
        guard let stamp else { return StrokePathBuilder.path(for: stroke) }
        let key = "\(stroke.id.uuidString)#\(stamp)" as NSString
        if let hit = paths.object(forKey: key) { return hit.path }
        let path = StrokePathBuilder.path(for: stroke)
        paths.setObject(PathBox(path), forKey: key)
        return path
    }
}

/// Decoded images for image elements, keyed by file URL. Thread safe.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let images = NSCache<NSURL, CGImage>()

    private init() {
        images.totalCostLimit = 256 * 1024 * 1024
    }

    func image(at url: URL) -> CGImage? {
        if let img = images.object(forKey: url as NSURL) { return img }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let img = CGImageSourceCreateImageAtIndex(src, 0, options as CFDictionary) else { return nil }
        images.setObject(img, forKey: url as NSURL, cost: img.bytesPerRow * img.height)
        return img
    }
}

/// Opened PDF files for PDF page backgrounds, keyed by file URL. Thread safe.
final class PDFCache: @unchecked Sendable {
    static let shared = PDFCache()

    private let documents = NSCache<NSURL, CGPDFDocument>()

    private init() {
        documents.countLimit = 12
    }

    func document(_ url: URL) -> CGPDFDocument? {
        if let doc = documents.object(forKey: url as NSURL) { return doc }
        guard let doc = CGPDFDocument(url as CFURL) else { return nil }
        if doc.isEncrypted && !doc.isUnlocked { _ = doc.unlockWithPassword("") }
        documents.setObject(doc, forKey: url as NSURL)
        return doc
    }

    /// Zero-based page lookup.
    func page(_ url: URL, index: Int) -> CGPDFPage? {
        document(url)?.page(at: index + 1)
    }
}

/// Draws page content into any y-down CGContext in page coordinates.
/// Used by the tiled page layers, the live overlay, and export.
struct PageRenderer {
    var assetsURL: URL

    // MARK: Background

    func drawBackground(_ bg: PageBackground, pageSize: CGSize, in ctx: CGContext, clip: CGRect) {
        let pageRect = CGRect(origin: .zero, size: pageSize)
        let rect = clip.intersection(pageRect)
        guard !rect.isNull else { return }
        ctx.setFillColor(bg.color.cgColor)
        ctx.fill(rect)

        if let source = bg.pdf,
           let page = PDFCache.shared.page(assetsURL.appendingPathComponent(source.assetName), index: source.pageIndex) {
            drawPDFPage(page, pageSize: pageSize, in: ctx, clip: rect)
        }

        let spacing = max(bg.spacing, 4)
        let lineWidth: CGFloat = 0.5
        ctx.setStrokeColor(bg.lineColor.cgColor)
        ctx.setLineWidth(lineWidth)

        func hLines(step: CGFloat, from top: CGFloat = 0) {
            guard step > 0 else { return }
            var y = top + (max(0, ceil((rect.minY - top) / step)) * step)
            while y <= rect.maxY {
                ctx.move(to: CGPoint(x: rect.minX, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
                y += step
            }
        }
        func vLines(step: CGFloat) {
            var x = ceil(rect.minX / step) * step
            while x <= rect.maxX {
                ctx.move(to: CGPoint(x: x, y: rect.minY))
                ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
                x += step
            }
        }

        switch bg.template {
        case .blank:
            break
        case .ruled:
            let top = spacing * 3
            hLines(step: spacing, from: top)
            ctx.strokePath()
            // Margin line.
            let marginX = min(72, pageSize.width * 0.12)
            if rect.minX <= marginX && rect.maxX >= marginX {
                ctx.setStrokeColor(bg.marginColor.cgColor)
                ctx.setLineWidth(0.75)
                ctx.move(to: CGPoint(x: marginX, y: rect.minY))
                ctx.addLine(to: CGPoint(x: marginX, y: rect.maxY))
                ctx.strokePath()
            }
        case .grid:
            hLines(step: spacing)
            vLines(step: spacing)
            ctx.strokePath()
        case .dotted:
            ctx.setFillColor(bg.lineColor.withAlpha(min(1, bg.lineColor.a * 1.8)).cgColor)
            let r: CGFloat = 0.9
            var y = ceil(rect.minY / spacing) * spacing
            while y <= rect.maxY + r {
                var x = ceil(rect.minX / spacing) * spacing
                while x <= rect.maxX + r {
                    ctx.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                    x += spacing
                }
                y += spacing
            }
            ctx.fillPath()
        case .isometric:
            // Lines at ±30° and verticals: an equilateral triangle grid.
            let dx = spacing * sqrt(3) / 2
            vLines(step: dx)
            let slope = tan(CGFloat.pi / 6)
            let span = rect.width * slope
            for sign in [CGFloat(1), -1] {
                // Lines y = sign·slope·x + c, with c on a lattice of `spacing`.
                let cs = [rect.minY - sign * slope * rect.minX, rect.minY - sign * slope * rect.maxX,
                          rect.maxY - sign * slope * rect.minX, rect.maxY - sign * slope * rect.maxX]
                var c = floor((cs.min()! - span) / spacing) * spacing
                let cMax = cs.max()! + span
                while c <= cMax {
                    ctx.move(to: CGPoint(x: rect.minX, y: sign * slope * rect.minX + c))
                    ctx.addLine(to: CGPoint(x: rect.maxX, y: sign * slope * rect.maxX + c))
                    c += spacing
                }
            }
            ctx.strokePath()
        case .cornell:
            // Title band, cue column, note lines and a summary box.
            let top = min(110, pageSize.height * 0.12)
            let summary = min(170, pageSize.height * 0.2)
            let cue = pageSize.width * 0.3
            let noteBottom = pageSize.height - summary
            ctx.saveGState()
            ctx.clip(to: CGRect(x: cue, y: top, width: pageSize.width - cue, height: noteBottom - top).intersection(rect))
            hLines(step: spacing, from: top + spacing)
            ctx.strokePath()
            ctx.restoreGState()
            ctx.setStrokeColor(bg.marginColor.cgColor)
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: 0, y: top)); ctx.addLine(to: CGPoint(x: pageSize.width, y: top))
            ctx.move(to: CGPoint(x: cue, y: top)); ctx.addLine(to: CGPoint(x: cue, y: noteBottom))
            ctx.move(to: CGPoint(x: 0, y: noteBottom)); ctx.addLine(to: CGPoint(x: pageSize.width, y: noteBottom))
            ctx.strokePath()
        case .lab:
            // Header with fields, then a fine grid with a heavier line every 5 squares.
            let header = min(96, pageSize.height * 0.1)
            ctx.setStrokeColor(bg.marginColor.cgColor)
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: 0, y: header)); ctx.addLine(to: CGPoint(x: pageSize.width, y: header))
            for f in [0.34, 0.67] {
                ctx.move(to: CGPoint(x: pageSize.width * f, y: header * 0.25))
                ctx.addLine(to: CGPoint(x: pageSize.width * f, y: header))
            }
            ctx.strokePath()
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: header, width: pageSize.width, height: pageSize.height - header).intersection(rect))
            ctx.setStrokeColor(bg.lineColor.cgColor)
            ctx.setLineWidth(0.35)
            hLines(step: spacing, from: header)
            vLines(step: spacing)
            ctx.strokePath()
            ctx.setLineWidth(0.8)
            hLines(step: spacing * 5, from: header)
            vLines(step: spacing * 5)
            ctx.strokePath()
            ctx.restoreGState()
        case .engineering:
            let minor = spacing / 5
            ctx.setLineWidth(0.35)
            hLines(step: minor)
            vLines(step: minor)
            ctx.strokePath()
            ctx.setLineWidth(0.9)
            hLines(step: spacing)
            vLines(step: spacing)
            ctx.strokePath()
        }
    }

    /// Draws an imported PDF page (vector) filling the page.
    private func drawPDFPage(_ page: CGPDFPage, pageSize: CGSize, in ctx: CGContext, clip: CGRect) {
        ctx.saveGState()
        ctx.clip(to: clip)
        // Our contexts are y-down; PDF drawing is y-up.
        ctx.translateBy(x: 0, y: pageSize.height)
        ctx.scaleBy(x: 1, y: -1)
        // Scale the PDF page to fill the page (CGPDFPage's own drawing
        // transform only ever scales down, so a small PDF on a large page
        // would sit in the middle). Aspect ratio is kept; the page is centered.
        let box = page.getBoxRect(.cropBox)
        if box.width > 0, box.height > 0 {
            let scale = min(pageSize.width / box.width, pageSize.height / box.height)
            ctx.translateBy(x: (pageSize.width - box.width * scale) / 2, y: (pageSize.height - box.height * scale) / 2)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -box.minX, y: -box.minY)
        }
        ctx.clip(to: box)
        ctx.interpolationQuality = .high
        ctx.setRenderingIntent(.defaultIntent)
        ctx.drawPDFPage(page)
        ctx.restoreGState()
    }

    // MARK: Elements

    func draw(_ items: [RenderItem], in ctx: CGContext, background: PageBackground) {
        for item in items { draw(item.element, stamp: item.stamp, in: ctx, background: background) }
    }

    func draw(_ element: CanvasElement, stamp: UInt64?, in ctx: CGContext, background: PageBackground) {
        switch element {
        case let .stroke(s): drawStroke(s, stamp: stamp, in: ctx, background: background)
        case let .shape(s): drawShape(s, in: ctx)
        case let .image(i): drawImage(i, in: ctx)
        case let .text(t): TextLayout.draw(t, in: ctx)
        }
    }

    func drawStroke(_ s: Stroke, stamp: UInt64?, in ctx: CGContext, background: PageBackground) {
        let path = RenderCache.shared.strokePath(for: s, stamp: stamp)
        ctx.saveGState()
        if s.style.isHighlighter && !background.isDark {
            // Multiply keeps text under the highlight crisp and dark.
            ctx.setBlendMode(.multiply)
        }
        ctx.setFillColor(s.style.color.withAlpha(s.style.color.a * Double(s.style.opacity)).cgColor)
        ctx.addPath(path)
        ctx.fillPath(using: .winding)
        ctx.restoreGState()
    }

    func drawShape(_ s: ShapeElement, in ctx: CGContext) {
        ctx.saveGState()
        let usesLayer = s.style.opacity < 0.999
        if usesLayer {
            ctx.setAlpha(s.style.opacity)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        let path = s.path()
        if let fill = s.style.fillColor, s.geometry.isClosed {
            ctx.setFillColor(fill.cgColor)
            ctx.addPath(s.path(trimForArrows: false))
            ctx.fillPath()
        }
        ctx.setStrokeColor(s.style.strokeColor.cgColor)
        ctx.setLineWidth(s.style.lineWidth)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        if let dash = s.style.lineStyle.dashPattern(width: s.style.lineWidth) {
            ctx.setLineDash(phase: 0, lengths: dash)
        }
        ctx.addPath(path)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        let heads = s.arrowHeadTriangles
        if !heads.isEmpty {
            ctx.setFillColor(s.style.strokeColor.cgColor)
            for tri in heads {
                ctx.move(to: tri[0])
                ctx.addLine(to: tri[1])
                ctx.addLine(to: tri[2])
                ctx.closePath()
            }
            ctx.drawPath(using: .fillStroke)
        }
        if usesLayer { ctx.endTransparencyLayer() }
        ctx.restoreGState()
    }

    func drawImage(_ i: ImageElement, in ctx: CGContext) {
        let url = assetsURL.appendingPathComponent(i.assetName)
        ctx.saveGState()
        ctx.concatenate(i.box.transform)
        ctx.setAlpha(i.opacity)
        let rect = i.box.localRect
        if let img = ImageCache.shared.image(at: url) {
            ctx.interpolationQuality = .high
            // CGContext draws images y-up; flip about the box center.
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(img, in: rect)
        } else {
            ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
            ctx.fill(rect)
        }
        ctx.restoreGState()
    }

    /// Renders a whole page (used for export and previews).
    func drawPage(_ page: PageData, in ctx: CGContext) {
        let rect = CGRect(origin: .zero, size: page.size)
        drawBackground(page.background, pageSize: page.size, in: ctx, clip: rect)
        ctx.saveGState()
        ctx.clip(to: rect)
        for e in page.elements { draw(e, stamp: nil, in: ctx, background: page.background) }
        ctx.restoreGState()
    }
}
