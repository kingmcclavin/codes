import CoreGraphics
import UIKit

/// Stroke (object) eraser and partial ("pixel") eraser. The partial eraser
/// splits vector strokes rather than painting background over them.
@MainActor
final class EraserTool: CanvasTool {
    private unowned let host: ToolHost
    private var pageID: UUID?
    private var lastPoint: CGPoint?
    private var applied: [EditCommand] = []
    private var cursor: (point: CGPoint, pageID: UUID)?

    init(host: ToolHost) { self.host = host }

    private var radius: CGFloat {
        host.settings.eraser.size / 2 / max(host.zoomScale, 0.01)
    }

    func began(_ input: ToolInput) {
        guard let first = input.samples.first else { return }
        pageID = input.pageID
        applied = []
        lastPoint = first.location
        erase(along: input.samples.map(\.location))
        moveCursor(to: input.samples.last?.location, pageID: input.pageID)
    }

    func moved(_ input: ToolInput) {
        guard pageID != nil, let last = lastPoint else { return }
        let path = [last] + input.samples.map(\.location)
        erase(along: path)
        lastPoint = path.last
        moveCursor(to: lastPoint, pageID: input.pageID)
    }

    func ended(_ input: ToolInput) {
        if pageID != nil, let last = lastPoint, !input.samples.isEmpty {
            erase(along: [last] + input.samples.map(\.location))
        }
        finish()
        moveCursor(to: nil, pageID: nil)
    }

    func cancelled() {
        finish()
        moveCursor(to: nil, pageID: nil)
    }

    func deactivate() { cancelled() }

    func hover(at location: CGPoint?, pageID: UUID?) {
        guard self.pageID == nil else { return }
        moveCursor(to: location, pageID: pageID)
    }

    private func finish() {
        if !applied.isEmpty {
            host.history.record(CompositeCommand(name: "Erase", commands: applied))
        }
        applied = []
        pageID = nil
        lastPoint = nil
    }

    private func erase(along path: [CGPoint]) {
        guard let pageID, let page = host.document.page(pageID), !path.isEmpty else { return }
        let r = radius
        let settings = host.settings.eraser
        let region = CGRect.bounding(path).expanded(by: r + 2)
        // Descending z so edits never invalidate the indices of later ones.
        let candidates = page.elements(in: region).compactMap { e -> (Int, CanvasElement)? in
            if settings.erasesHighlighterOnly {
                guard case let .stroke(s) = e, s.style.isHighlighter else { return nil }
            }
            return page.index(of: e.id).map { ($0, e) }
        }.sorted { $0.0 > $1.0 }

        for (index, element) in candidates {
            let edit: ElementsEdit?
            switch (settings.mode, element) {
            case (.object, _):
                edit = element.intersects(path: path, radius: r)
                    ? ElementsEdit(name: "Erase", pageID: pageID, removed: [IndexedElement(index: index, element: element)])
                    : nil
            case let (.partial, .stroke(stroke)):
                edit = ErasureEngine.erase(stroke, along: path, radius: r).map {
                    ElementsEdit.replace(element, at: index, with: $0.map { .stroke($0) }, page: page, name: "Erase")
                }
            case let (.partial, .shape(shape)):
                guard element.intersects(path: path, radius: r) else { edit = nil; break }
                // Shapes become ink so only the touched part disappears.
                var pieces: [CanvasElement] = []
                for s in shape.asStrokes() {
                    if let fragments = ErasureEngine.erase(s, along: path, radius: r) {
                        pieces += fragments.map { .stroke($0) }
                    } else {
                        pieces.append(.stroke(s))
                    }
                }
                edit = ElementsEdit.replace(element, at: index, with: pieces, page: page, name: "Erase")
            case (.partial, _):
                // Images and text are only removed by the stroke eraser.
                edit = nil
            }
            if let edit {
                edit.apply(to: host.document)
                applied.append(edit)
            }
        }
    }

    private func moveCursor(to point: CGPoint?, pageID: UUID?) {
        let old = cursor
        cursor = point.flatMap { p in pageID.map { (p, $0) } }
        let pad = host.settings.eraser.size / 2 + 3
        for c in [old, cursor].compactMap({ $0 }) {
            let t = host.pageToOverlay(c.pageID)
            let center = c.point.applying(t)
            host.invalidateOverlayScreenRect(CGRect(x: center.x - pad, y: center.y - pad, width: 2 * pad, height: 2 * pad))
        }
    }

    func drawOverlay(in ctx: CGContext) {
        guard let cursor else { return }
        let center = cursor.point.applying(host.pageToOverlay(cursor.pageID))
        let r = host.settings.eraser.size / 2
        let rect = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
        ctx.setFillColor(UIColor.systemBackground.withAlphaComponent(0.35).cgColor)
        ctx.fillEllipse(in: rect)
        ctx.setStrokeColor(UIColor.secondaryLabel.cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: rect.insetBy(dx: 0.5, dy: 0.5))
    }
}
