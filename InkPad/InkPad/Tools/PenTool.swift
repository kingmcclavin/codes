import CoreGraphics
import UIKit

/// Freehand ink (pen / highlighter) plus the Shapes tool.
///
/// * Pen & highlighter: hold the pencil still at the end of a stroke to snap
///   it to a clean shape; scribble quickly over existing content to erase it.
/// * Shapes: every stroke is converted to geometry on lift.
@MainActor
final class PenTool: CanvasTool {
    enum Mode { case pen, highlighter, shapes }

    let mode: Mode
    private unowned let host: ToolHost
    private let recognizer = ShapeRecognizer()
    private let scribbleDetector = ScribbleDetector()

    private var pageID: UUID?
    private var style = PenPreset.ballpoint.style
    private var points: [InkPoint] = []
    private var predicted: [InkPoint] = []
    private var startTime: TimeInterval = 0
    private var estimation: [NSNumber: Int] = [:]
    private var lastPredictedRect = CGRect.null

    // Hold-to-snap state.
    private var holdTimer: Timer?
    private var holdAnchor = CGPoint.zero
    private var holdIndex = 0
    private var previewShape: ShapeElement?
    private var previewUpgrade: (lineID: UUID, atEnd: Bool)?

    init(host: ToolHost, mode: Mode) {
        self.host = host
        self.mode = mode
    }

    private var isActive: Bool { pageID != nil }

    private func currentStyle() -> StrokeStyle {
        let s = host.settings
        switch mode {
        case .pen: return s.pen
        case .highlighter: return s.highlighter
        case .shapes:
            return StrokeStyle(kind: .fineliner, color: s.shape.strokeColor, width: s.shape.lineWidth,
                               opacity: s.shape.opacity, pressureSensitivity: 0, lineStyle: s.shape.lineStyle)
        }
    }

    private func shapeStyle() -> ShapeStyle {
        switch mode {
        case .shapes: return host.settings.shape
        case .pen, .highlighter:
            return ShapeStyle(strokeColor: style.color, lineWidth: style.width, opacity: style.opacity,
                              fillColor: nil, lineStyle: style.lineStyle)
        }
    }

    // MARK: Input

    func began(_ input: ToolInput) {
        guard let first = input.samples.first else { return }
        reset()
        pageID = input.pageID
        style = currentStyle()
        startTime = first.timestamp
        append(input.samples)
        predicted = input.predicted.map { $0.inkPoint(startTime: startTime) }
        holdAnchor = first.location
        holdIndex = 0
        restartHoldTimer()
        invalidateTail()
    }

    func moved(_ input: ToolInput) {
        guard isActive else { return }
        if previewShape != nil || previewUpgrade != nil {
            // Keep the snapped shape while the pencil rests; moving away
            // decisively returns to freehand.
            guard let last = input.last, last.location.distance(to: holdAnchor) * host.zoomScale > 20 else { return }
            previewShape = nil
            previewUpgrade = nil
            invalidateWholeStroke()
        }
        append(input.samples)
        predicted = input.predicted.map { $0.inkPoint(startTime: startTime) }
        if let last = input.last, last.location.distance(to: holdAnchor) * host.zoomScale > 2.5 {
            holdAnchor = last.location
            holdIndex = points.count
            restartHoldTimer()
        }
        invalidateTail()
    }

    func ended(_ input: ToolInput) {
        guard isActive else { return }
        if previewShape == nil && previewUpgrade == nil { append(input.samples) }
        predicted = []
        holdTimer?.invalidate()
        commit()
    }

    func cancelled() {
        guard isActive else { return }
        invalidateWholeStroke()
        reset()
    }

    func deactivate() { cancelled() }

    func updateEstimated(_ samples: [InputSample]) {
        guard isActive else { return }
        var dirty = CGRect.null
        for s in samples {
            guard let idx = s.estimationIndex, let i = estimation[idx], points.indices.contains(i) else { continue }
            points[i].force = Float(s.force)
            points[i].altitude = Float(s.altitude)
            points[i].azimuth = Float(s.azimuth)
            dirty = dirty.union(CGRect(origin: points[i].location, size: .zero))
        }
        if !dirty.isNull, let pageID {
            host.invalidateOverlay(pageRect: dirty.expanded(by: style.maximumWidth * 3 + 4), pageID: pageID)
        }
    }

    private func append(_ samples: [InputSample]) {
        let minSpacing = 0.15 / max(host.zoomScale, 0.01)
        for s in samples {
            let p = s.inkPoint(startTime: startTime)
            if let last = points.last, last.location.distance(to: p.location) < minSpacing {
                // Keep the higher pressure of merged samples.
                points[points.count - 1].force = max(last.force, p.force)
                continue
            }
            points.append(p)
            if let idx = s.estimationIndex { estimation[idx] = points.count - 1 }
        }
    }

    private func reset() {
        holdTimer?.invalidate()
        holdTimer = nil
        pageID = nil
        points = []
        predicted = []
        estimation = [:]
        previewShape = nil
        previewUpgrade = nil
        lastPredictedRect = .null
    }

    // MARK: Hold to snap

    private func restartHoldTimer() {
        holdTimer?.invalidate()
        guard host.settings.holdToSnapShapes || mode == .shapes else { return }
        let timer = Timer(timeInterval: host.settings.holdDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.holdFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    private func holdFired() {
        guard isActive, points.count >= 3 else { return }
        let locs = points[0..<max(min(holdIndex + 1, points.count), 2)].map(\.location)
        guard Geometry.pathLength(locs) * host.zoomScale > 16 else { return }
        switch recognizer.recognize(locs, context: recognitionContext(for: locs)) {
        case let .shape(geometry, arrows)?:
            previewShape = ShapeElement(geometry: geometry, style: shapeStyle(), arrows: arrows)
        case let .addArrowHead(lineID, atEnd)?:
            previewUpgrade = (lineID, atEnd)
        case nil:
            return
        }
        predicted = []
        invalidateWholeStroke()
    }

    private func recognitionContext(for locs: [CGPoint]) -> RecognitionContext {
        var ctx = RecognitionContext()
        ctx.snapTolerance = 12 / max(host.zoomScale, 0.01)
        guard let pageID, let page = host.document.page(pageID) else { return ctx }
        let region = CGRect.bounding(locs).expanded(by: 60 / max(host.zoomScale, 0.01))
        for e in page.elements(in: region) {
            guard case let .shape(s) = e else { continue }
            ctx.snapPoints.append(contentsOf: s.keyPoints)
            if case let .line(a, b) = s.geometry { ctx.lines.append((s.id, a, b)) }
        }
        return ctx
    }

    // MARK: Commit

    private func commit() {
        defer { reset() }
        guard let pageID, let page = host.document.page(pageID), !points.isEmpty else { return }
        invalidateWholeStroke()

        if let upgrade = previewUpgrade {
            applyArrowUpgrade(upgrade, page: page)
            return
        }
        if let shape = previewShape {
            addShape(shape, page: page)
            return
        }
        let locs = points.map(\.location)
        if mode == .shapes {
            let diag = CGRect.bounding(locs).diagonal
            if Geometry.pathLength(locs) * host.zoomScale < 4 { return }
            switch recognizer.recognize(locs, context: recognitionContext(for: locs)) {
            case let .shape(g, arrows)?:
                addShape(ShapeElement(geometry: g, style: shapeStyle(), arrows: arrows), page: page)
            case let .addArrowHead(id, atEnd)?:
                applyArrowUpgrade((id, atEnd), page: page)
            case nil:
                addShape(ShapeElement(geometry: recognizer.fitCurve(locs, diag: diag), style: shapeStyle()), page: page)
            }
            return
        }
        if mode == .pen, host.settings.scribbleToErase, points.count >= 12,
           scribbleDetector.isScribble(points: locs, times: points.map { TimeInterval($0.t) }, zoom: host.zoomScale),
           let erase = ScribbleEraser.command(for: locs, on: page, mode: host.settings.scribbleMode,
                                              tolerance: max(style.width / 2, 1.5) + 2 / max(host.zoomScale, 0.01)) {
            host.history.perform(erase)
            return
        }

        let stroke = Stroke(points: points, style: style)
        let element = CanvasElement.stroke(stroke)
        host.history.perform(ElementsEdit.add([element], to: page, name: mode == .highlighter ? "Highlight" : "Ink"))
        host.showPending([element], pageID: pageID)
    }

    private func addShape(_ shape: ShapeElement, page: PageStore) {
        let element: CanvasElement
        if mode == .highlighter, case let .line(a, b) = shape.geometry {
            // Straight highlight keeps the highlighter look (multiply blending).
            let pts = Geometry.resample([a, b], spacing: max(2, style.width / 2)).map { InkPoint(location: $0) }
            var s = style
            s.pressureSensitivity = 0
            element = .stroke(Stroke(points: pts, style: s))
        } else {
            element = .shape(shape)
        }
        host.history.perform(ElementsEdit.add([element], to: page, name: "Shape"))
        host.showPending([element], pageID: page.id)
    }

    private func applyArrowUpgrade(_ upgrade: (lineID: UUID, atEnd: Bool), page: PageStore) {
        guard case var .shape(line)? = page.element(upgrade.lineID) else { return }
        let before = CanvasElement.shape(line)
        if upgrade.atEnd { line.arrows.end = true } else { line.arrows.start = true }
        let after = CanvasElement.shape(line)
        host.history.perform(ElementsEdit.update([(before, after)], page: page, name: "Arrow Head"))
        host.showPending([after], pageID: page.id)
    }

    // MARK: Overlay

    private func upgradedLinePreview() -> ShapeElement? {
        guard let upgrade = previewUpgrade, let pageID,
              case var .shape(line)? = host.document.page(pageID)?.element(upgrade.lineID) else { return nil }
        if upgrade.atEnd { line.arrows.end = true } else { line.arrows.start = true }
        return line
    }

    func drawOverlay(in ctx: CGContext) {
        guard let pageID, !points.isEmpty else { return }
        ctx.saveGState()
        ctx.concatenate(host.pageToOverlay(pageID))
        if let shape = previewShape ?? upgradedLinePreview() {
            host.renderer.drawShape(shape, in: ctx)
        } else {
            let path = StrokePathBuilder.path(points: points + predicted, style: style)
            ctx.setFillColor(style.color.withAlpha(style.color.a * Double(style.opacity)).cgColor)
            ctx.addPath(path)
            ctx.fillPath(using: .winding)
        }
        ctx.restoreGState()
    }

    private func invalidateTail() {
        guard let pageID else { return }
        let tail = points.suffix(10).map(\.location)
        let predictedLocs = predicted.map(\.location)
        let pad = style.maximumWidth + 3
        var rect = CGRect.bounding(tail + predictedLocs).expanded(by: pad)
        if !lastPredictedRect.isNull { rect = rect.union(lastPredictedRect) }
        lastPredictedRect = predictedLocs.isEmpty ? .null : CGRect.bounding(predictedLocs + tail.suffix(1)).expanded(by: pad)
        host.invalidateOverlay(pageRect: rect, pageID: pageID)
    }

    private func invalidateWholeStroke() {
        guard let pageID else { return }
        var rect = CGRect.bounding((points + predicted).map(\.location)).expanded(by: style.maximumWidth + 3)
        if let shape = previewShape ?? upgradedLinePreview() { rect = rect.union(shape.bounds) }
        if !lastPredictedRect.isNull { rect = rect.union(lastPredictedRect) }
        host.invalidateOverlay(pageRect: rect, pageID: pageID)
    }
}
