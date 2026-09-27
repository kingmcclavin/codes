import CoreGraphics
import UIKit

/// Current selection and its in-flight transform. Selected elements are
/// "lifted" (hidden from the tiled page and drawn in the overlay) only while
/// they are being manipulated.
@MainActor
final class SelectionController {
    enum Handle: Equatable {
        case corner(sx: CGFloat, sy: CGFloat)
        case edge(sx: CGFloat, sy: CGFloat)   // one of sx / sy is 0
        case rotate
    }

    private(set) var pageID: UUID?
    private(set) var ids: [UUID] = []
    /// Selection frame in page coordinates, before `liveTransform`.
    private(set) var box = BoxGeometry(center: .zero, size: .zero)
    var liveTransform: CGAffineTransform = .identity
    private(set) var isLifted = false
    /// Whether non-uniform scaling is allowed (no ink or text selected).
    private(set) var allowsNonUniformScale = false
    private(set) var liftedElements: [RenderItem] = []

    var isEmpty: Bool { ids.isEmpty }
    var currentBox: BoxGeometry { box.applying(liveTransform) }

    func select(_ elements: [CanvasElement], pageID: UUID) {
        guard !elements.isEmpty else { clear(); return }
        self.pageID = pageID
        ids = elements.map(\.id)
        liveTransform = .identity
        allowsNonUniformScale = elements.allSatisfy { e in
            switch e { case .shape, .image: return true; default: return false }
        }
        if elements.count == 1, let b = elements[0].box {
            box = b
        } else {
            let r = elements.reduce(CGRect.null) { $0.union($1.bounds) }
            box = BoxGeometry(rect: r)
        }
    }

    func clear() {
        pageID = nil
        ids = []
        liveTransform = .identity
        isLifted = false
        liftedElements = []
    }

    /// Recomputes the frame after the selected elements changed (e.g. restyled).
    func refresh(from page: PageStore) {
        let elements = ids.compactMap { page.element($0) }
        if elements.isEmpty { clear() } else { select(elements, pageID: page.id) }
    }

    func lift(from document: DocumentModel) {
        guard !isLifted, let pageID, let page = document.page(pageID) else { return }
        liftedElements = ids.compactMap { id in page.element(id).map { RenderItem(element: $0, stamp: page.stamp(for: id)) } }
        document.setHidden(Set(ids), page: pageID)
        isLifted = true
    }

    /// Commits `liveTransform` into the frame; returns the transform applied.
    func settle(in document: DocumentModel) -> CGAffineTransform {
        let t = liveTransform
        box = box.applying(t)
        liveTransform = .identity
        if isLifted, let pageID { document.setHidden([], page: pageID) }
        isLifted = false
        liftedElements = []
        return t
    }

    // MARK: Handles (overlay coordinates)

    func handlePoints(pageToOverlay t: CGAffineTransform) -> [(Handle, CGPoint)] {
        let b = currentBox
        let bt = b.transform.concatenating(t)
        let hw = b.size.width / 2, hh = b.size.height / 2
        var result: [(Handle, CGPoint)] = []
        for sx in [-1, 1] as [CGFloat] {
            for sy in [-1, 1] as [CGFloat] {
                result.append((.corner(sx: sx, sy: sy), CGPoint(x: sx * hw, y: sy * hh).applying(bt)))
            }
        }
        if allowsNonUniformScale {
            result.append((.edge(sx: 1, sy: 0), CGPoint(x: hw, y: 0).applying(bt)))
            result.append((.edge(sx: -1, sy: 0), CGPoint(x: -hw, y: 0).applying(bt)))
            result.append((.edge(sx: 0, sy: 1), CGPoint(x: 0, y: hh).applying(bt)))
            result.append((.edge(sx: 0, sy: -1), CGPoint(x: 0, y: -hh).applying(bt)))
        }
        let top = CGPoint(x: 0, y: -hh).applying(bt)
        let center = CGPoint.zero.applying(bt)
        var up = (top - center).normalized
        if up == .zero { up = CGPoint(x: 0, y: -1) }
        result.append((.rotate, top + up * 28))
        return result
    }

    func handle(at overlayPoint: CGPoint, pageToOverlay t: CGAffineTransform) -> Handle? {
        var best: (Handle, CGFloat)?
        for (h, p) in handlePoints(pageToOverlay: t) {
            let d = p.distance(to: overlayPoint)
            if d < 24, d < (best?.1 ?? .greatestFiniteMagnitude) { best = (h, d) }
        }
        return best?.0
    }

    // MARK: Manipulation math (page coordinates)

    func resizeTransform(handle: Handle, to p: CGPoint, uniform: Bool) -> CGAffineTransform {
        let bt = box.transform
        let local = p.applying(bt.inverted())
        let hw = max(box.size.width / 2, 0.5), hh = max(box.size.height / 2, 0.5)
        var sxSign: CGFloat = 0, sySign: CGFloat = 0
        switch handle {
        case let .corner(sx, sy): sxSign = sx; sySign = sy
        case let .edge(sx, sy): sxSign = sx; sySign = sy
        case .rotate: return .identity
        }
        let fixed = CGPoint(x: -sxSign * hw, y: -sySign * hh)
        var scaleX: CGFloat = 1, scaleY: CGFloat = 1
        if sxSign != 0 { scaleX = ((local.x - fixed.x) * sxSign) / (2 * hw) }
        if sySign != 0 { scaleY = ((local.y - fixed.y) * sySign) / (2 * hh) }
        if case .corner = handle, uniform || !allowsNonUniformScale {
            // Project onto the diagonal for a smooth uniform scale.
            let diag = CGPoint(x: sxSign * 2 * hw, y: sySign * 2 * hh)
            let s = (local - fixed).dot(diag) / diag.lengthSquared
            scaleX = s; scaleY = s
        } else if case .edge = handle, !allowsNonUniformScale {
            let s = sxSign != 0 ? scaleX : scaleY
            scaleX = s; scaleY = s
        }
        scaleX = max(scaleX, 0.05); scaleY = max(scaleY, 0.05)
        let l = CGAffineTransform(translationX: -fixed.x, y: -fixed.y)
            .concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY))
            .concatenating(CGAffineTransform(translationX: fixed.x, y: fixed.y))
        return bt.inverted().concatenating(l).concatenating(bt)
    }

    func rotateTransform(from start: CGPoint, to p: CGPoint) -> CGAffineTransform {
        let c = box.center
        var angle = (p - c).angle - (start - c).angle
        // Magnetic snapping to multiples of 45° of the absolute rotation.
        let absolute = box.rotation + angle
        let step = CGFloat.pi / 4
        let nearest = (absolute / step).rounded() * step
        if abs(absolute - nearest) < 4 * .pi / 180 { angle = nearest - box.rotation }
        return CGAffineTransform(translationX: -c.x, y: -c.y)
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(CGAffineTransform(translationX: c.x, y: c.y))
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, pageToOverlay t: CGAffineTransform, renderer: PageRenderer, background: PageBackground) {
        guard !isEmpty else { return }
        if isLifted {
            ctx.saveGState()
            ctx.concatenate(liveTransform.concatenating(t))
            renderer.draw(liftedElements, in: ctx, background: background)
            ctx.restoreGState()
        }
        let b = currentBox
        let corners = b.corners.map { $0.applying(t) }
        let tint = UIColor.systemBlue
        ctx.saveGState()
        ctx.setStrokeColor(tint.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [5, 4])
        ctx.addLines(between: corners + [corners[0]])
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])

        let handles = handlePoints(pageToOverlay: t)
        if let rot = handles.first(where: { $0.0 == .rotate })?.1 {
            let topMid = corners[0].midpoint(corners[1])
            ctx.move(to: topMid)
            ctx.addLine(to: rot)
            ctx.strokePath()
        }
        for (h, p) in handles {
            let r: CGFloat = h == .rotate ? 7 : 6
            let rect = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(tint.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: rect)
        }
        ctx.restoreGState()
    }

    /// Screen rect covering the selection and its handles.
    func overlayBounds(pageToOverlay t: CGAffineTransform) -> CGRect {
        guard !isEmpty else { return .null }
        var r = CGRect.bounding(currentBox.corners.map { $0.applying(t) })
        for (_, p) in handlePoints(pageToOverlay: t) { r = r.union(CGRect(origin: p, size: .zero)) }
        if isLifted {
            let full = liveTransform.concatenating(t)
            for item in liftedElements { r = r.union(item.element.bounds.applying(full)) }
        }
        return r.expanded(by: 12)
    }
}
