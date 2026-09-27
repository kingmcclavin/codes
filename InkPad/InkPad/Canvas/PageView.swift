import QuartzCore
import UIKit

/// Tiled vector layer. Each tile is rendered straight from the stroke data at
/// the tile's zoom level, so ink stays razor sharp at any magnification and
/// only the tiles touched by an edit are ever redrawn.
final class PageTiledLayer: CATiledLayer {
    override class func fadeDuration() -> CFTimeInterval { 0 }

    // Set once on the main thread before the layer is first displayed and
    // then only read from CoreAnimation's tile threads.
    var store: PageStore?
    var renderer: PageRenderer?
    var onTileDrawn: ((CGRect, UInt64) -> Void)?

    override func draw(in ctx: CGContext) {
        guard let store, let renderer else { return }
        let rect = ctx.boundingBoxOfClipPath
        let generation = store.generation
        let size = store.size
        let background = store.background
        renderer.drawBackground(background, pageSize: size, in: ctx, clip: rect)
        let items = store.renderItems(in: rect.expanded(by: 1))
        if !items.isEmpty {
            ctx.saveGState()
            ctx.clip(to: CGRect(origin: .zero, size: size))
            ctx.setShouldAntialias(true)
            ctx.setAllowsAntialiasing(true)
            renderer.draw(items, in: ctx, background: background)
            ctx.restoreGState()
        }
        onTileDrawn?(rect, generation)
    }
}

final class PageView: UIView {
    let pageID: UUID
    let store: PageStore

    override class var layerClass: AnyClass { PageTiledLayer.self }

    private var tiledLayer: PageTiledLayer { layer as! PageTiledLayer }

    init(store: PageStore, renderer: PageRenderer, onTileDrawn: @escaping (UUID, CGRect, UInt64) -> Void) {
        self.pageID = store.id
        self.store = store
        super.init(frame: CGRect(origin: .zero, size: store.size))
        let layer = tiledLayer
        layer.store = store
        layer.renderer = renderer
        let id = store.id
        layer.onTileDrawn = { rect, gen in
            DispatchQueue.main.async { onTileDrawn(id, rect, gen) }
        }
        layer.tileSize = CGSize(width: 512, height: 512)
        // 3 zoomed-out levels and 5 magnified levels (up to 32×).
        layer.levelsOfDetail = 8
        layer.levelsOfDetailBias = 5
        layer.drawsAsynchronously = true
        isOpaque = true
        backgroundColor = store.background.color.uiColor
        isUserInteractionEnabled = false

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)
        updateShadowPath()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var frame: CGRect {
        didSet { if oldValue.size != frame.size { updateShadowPath() } }
    }

    private func updateShadowPath() {
        layer.shadowPath = UIBezierPath(rect: bounds).cgPath
    }

    func invalidate(_ rect: CGRect) {
        tiledLayer.setNeedsDisplay(rect.expanded(by: 2))
    }

    func invalidateAll() {
        backgroundColor = store.background.color.uiColor
        tiledLayer.setNeedsDisplay()
    }
}

/// Screen-space overlay above the scroll view. Draws in-progress ink,
/// selections and tool feedback in *screen* coordinates so it is always
/// sharp and its backing store never grows with zoom.
final class OverlayView: UIView {
    var drawHandler: ((CGContext, CGRect) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        clearsContextBeforeDrawing = true
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        drawHandler?(ctx, rect)
    }
}
