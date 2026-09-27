import CoreGraphics
import UIKit

/// Lasso selection plus move / resize / rotate of the selection.
@MainActor
final class LassoTool: CanvasTool {
    private enum Drag {
        case none
        case lasso([CGPoint])
        case move(start: CGPoint)
        case resize(SelectionController.Handle)
        case rotate(start: CGPoint)
    }

    private unowned let host: ToolHost
    private var drag: Drag = .none
    private var pageID: UUID?
    private var startScreen: CGPoint = .zero
    private var movedEnough = false

    init(host: ToolHost) { self.host = host }

    private var selection: SelectionController { host.selection }

    func began(_ input: ToolInput) {
        guard let p = input.samples.first?.location else { return }
        pageID = input.pageID
        movedEnough = false
        let t = host.pageToOverlay(input.pageID)
        startScreen = p.applying(t)

        if !selection.isEmpty, selection.pageID == input.pageID {
            if let h = selection.handle(at: startScreen, pageToOverlay: t) {
                drag = h == .rotate ? .rotate(start: p) : .resize(h)
                return
            }
            if selection.currentBox.contains(p, tolerance: 12 / max(host.zoomScale, 0.01)) {
                drag = .move(start: p)
                return
            }
        }
        if !selection.isEmpty { clearSelection() }
        drag = input.isFinger ? .none : .lasso([p])
    }

    func moved(_ input: ToolInput) {
        guard let pageID, let p = input.last?.location else { return }
        let t = host.pageToOverlay(pageID)
        if !movedEnough, p.applying(t).distance(to: startScreen) > 3 { movedEnough = true }

        switch drag {
        case .none:
            return
        case var .lasso(points):
            points.append(contentsOf: input.samples.map(\.location))
            drag = .lasso(points)
            host.invalidateOverlay(pageRect: CGRect.bounding(points.suffix(input.samples.count + 2)).expanded(by: 4 / max(host.zoomScale, 0.01)),
                                   pageID: pageID)
            return
        case let .move(start):
            guard movedEnough else { return }
            let old = selection.overlayBounds(pageToOverlay: t)
            selection.lift(from: host.document)
            selection.liveTransform = CGAffineTransform(translationX: p.x - start.x, y: p.y - start.y)
            invalidateSelection(old: old, t: t)
        case let .resize(handle):
            guard movedEnough else { return }
            let old = selection.overlayBounds(pageToOverlay: t)
            selection.lift(from: host.document)
            selection.liveTransform = selection.resizeTransform(handle: handle, to: p, uniform: true)
            invalidateSelection(old: old, t: t)
        case let .rotate(start):
            guard movedEnough else { return }
            let old = selection.overlayBounds(pageToOverlay: t)
            selection.lift(from: host.document)
            selection.liveTransform = selection.rotateTransform(from: start, to: p)
            invalidateSelection(old: old, t: t)
        }
    }

    func ended(_ input: ToolInput) {
        if !input.samples.isEmpty { moved(input) }
        guard let pageID, let page = host.document.page(pageID) else { drag = .none; return }
        switch drag {
        case .none:
            break
        case let .lasso(points):
            host.invalidateOverlay()
            finishLasso(points, page: page)
        case .move, .resize, .rotate:
            if movedEnough { commitTransform(page: page) }
            host.presentSelectionMenu()
        }
        drag = .none
        self.pageID = nil
    }

    func cancelled() {
        if case .lasso = drag { host.invalidateOverlay() }
        if selection.isLifted {
            selection.liveTransform = .identity
            _ = selection.settle(in: host.document)
            host.invalidateOverlay()
        }
        drag = .none
        pageID = nil
    }

    func deactivate() {
        cancelled()
        clearSelection()
    }

    private func clearSelection() {
        guard !selection.isEmpty else { return }
        if selection.isLifted { _ = selection.settle(in: host.document) }
        selection.clear()
        host.selectionDidChange()
        host.invalidateOverlay()
    }

    private func invalidateSelection(old: CGRect, t: CGAffineTransform) {
        let new = selection.overlayBounds(pageToOverlay: t)
        host.invalidateOverlayScreenRect(old.union(new))
    }

    private func finishLasso(_ points: [CGPoint], page: PageStore) {
        let screenLength = Geometry.pathLength(points) * host.zoomScale
        if screenLength < 10, let p = points.first {
            // Tap: select the topmost element, or offer Paste on empty space.
            if let e = page.topElement(at: p, tolerance: 8 / max(host.zoomScale, 0.01)) {
                selection.select([e], pageID: page.id)
                host.selectionDidChange()
                host.invalidateOverlay()
                host.presentSelectionMenu()
            } else if Clipboard.hasContent {
                host.presentPasteMenu(at: p, pageID: page.id)
            }
            return
        }
        guard points.count >= 3 else { return }
        let hidden = page.hiddenIDs
        let found = page.elements(in: CGRect.bounding(points))
            .filter { !hidden.contains($0.id) && $0.isEnclosed(by: points) }
        selection.select(found, pageID: page.id)
        host.selectionDidChange()
        host.invalidateOverlay()
        if !found.isEmpty { host.presentSelectionMenu() }
    }

    private func commitTransform(page: PageStore) {
        let t = selection.liveTransform
        let ids = selection.ids
        let pairs: [(before: CanvasElement, after: CanvasElement)] = ids.compactMap { id in
            page.element(id).map { ($0, $0.transformed(by: t)) }
        }
        _ = selection.settle(in: host.document)
        guard t != .identity, !pairs.isEmpty else { return }
        host.history.perform(ElementsEdit.update(pairs, page: page, name: "Transform"))
        host.showPending(pairs.map(\.after), pageID: page.id)
        host.invalidateOverlay()
    }

    func drawOverlay(in ctx: CGContext) {
        guard case let .lasso(points) = drag, let pageID, points.count > 1 else { return }
        let t = host.pageToOverlay(pageID)
        let pts = points.map { $0.applying(t) }
        ctx.saveGState()
        ctx.setStrokeColor(UIColor.systemBlue.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.setLineJoin(.round)
        ctx.addLines(between: pts)
        ctx.strokePath()
        ctx.setFillColor(UIColor.systemBlue.withAlphaComponent(0.06).cgColor)
        ctx.addLines(between: pts)
        ctx.closePath()
        ctx.fillPath()
        ctx.restoreGState()
    }
}
