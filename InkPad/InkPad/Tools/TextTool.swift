import CoreGraphics
import UIKit

/// Tap to place a text box, tap existing text to edit it.
@MainActor
final class TextTool: CanvasTool {
    private unowned let host: ToolHost
    private var start: (point: CGPoint, pageID: UUID)?
    private var maxMove: CGFloat = 0

    init(host: ToolHost) { self.host = host }

    func began(_ input: ToolInput) {
        guard let p = input.samples.first?.location else { return }
        start = (p, input.pageID)
        maxMove = 0
    }

    func moved(_ input: ToolInput) {
        guard let start, let p = input.last?.location else { return }
        maxMove = max(maxMove, p.distance(to: start.point) * host.zoomScale)
    }

    func ended(_ input: ToolInput) {
        defer { start = nil }
        guard let start, maxMove < 12, let page = host.document.page(start.pageID) else { return }
        let p = start.point
        let hit = page.elements(in: CGRect(origin: p, size: .zero).expanded(by: 4)).last {
            if case .text = $0 { return $0.hitTest(p, tolerance: 4) }
            return false
        }
        if host.isEditingText {
            host.endTextEditing()
            if case let .text(t)? = hit { host.beginTextEditing(t, pageID: page.id, isNew: false) }
            return
        }
        if case let .text(t)? = hit {
            host.beginTextEditing(t, pageID: page.id, isNew: false)
            return
        }
        let style = host.settings.text
        let width = max(160, min(360, page.size.width - p.x - 24))
        let size = TextLayout.measure("", style: style, width: width)
        let origin = CGPoint(x: p.x, y: p.y - size.height / 2)
        let element = TextElement(text: "", style: style,
                                  box: BoxGeometry(rect: CGRect(origin: origin, size: size)))
        host.beginTextEditing(element, pageID: page.id, isNew: true)
    }

    func cancelled() { start = nil }

    func deactivate() {
        start = nil
        if host.isEditingText { host.endTextEditing() }
    }
}
