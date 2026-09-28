import PhotosUI
import UIKit

/// The drawing surface.
///
/// View hierarchy:
/// ```
/// view
/// ├─ scrollView            (fingers: pan / pinch; pencil: PencilInputRecognizer)
/// │   └─ container         (zoomed; unscaled page coordinates)
/// │       └─ PageView × n  (CATiledLayer, vector tiles)
/// ├─ overlay               (screen space: live ink, selection, cursors)
/// └─ text view             (only while editing text)
/// ```
@MainActor
final class CanvasViewController: UIViewController {
    let editor: EditorModel
    var document: DocumentModel { editor.document }
    var history: History { editor.history }
    var settings: ToolSettings { editor.settings }
    let renderer: PageRenderer
    let selection = SelectionController()

    private let scrollView = UIScrollView()
    private let container = UIView()
    private let overlay = OverlayView()
    private let pullToAdd = PullToAddPageView()
    private var pageViews: [UUID: PageView] = [:]
    private let pencilRecognizer = PencilInputRecognizer(target: nil, action: nil)
    private let selectionDrag = UIPanGestureRecognizer()
    private var editMenu: UIEditMenuInteraction!
    private var textEditing: TextEditingController!

    private var tools: [ToolKind: CanvasTool] = [:]
    private var activeKind: ToolKind = .pen
    private var activeTool: CanvasTool!
    private var activePageID: UUID?

    private struct Pending {
        var pageID: UUID
        var item: RenderItem
        var generation: UInt64
        var covered: CGRect
        var created: CFTimeInterval
    }
    private var pending: [Pending] = []

    private enum MenuContext {
        case selection
        case paste(point: CGPoint, pageID: UUID)
    }
    private var menuContext: MenuContext = .selection

    private let pageGap: CGFloat = 28
    private let pageMargin: CGFloat = 28
    private var didRestoreViewState = false
    private var lastLayoutSize: CGSize = .zero
    private var keyboardInset: CGFloat = 0

    init(editor: EditorModel) {
        self.editor = editor
        self.renderer = PageRenderer(assetsURL: editor.document.assetsURL)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.13, alpha: 1) : UIColor(white: 0.9, alpha: 1) }

        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.minimumZoomScale = 0.2
        scrollView.maximumZoomScale = 24
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceVertical = true
        scrollView.alwaysBounceHorizontal = false
        scrollView.isDirectionalLockEnabled = true
        scrollView.panGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.indirectPointer.rawValue),
        ]
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        view.addSubview(scrollView)
        scrollView.addSubview(container)

        pullToAdd.frame = view.bounds
        pullToAdd.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(pullToAdd)

        overlay.frame = view.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.drawHandler = { [weak self] ctx, rect in self?.drawOverlay(ctx, rect) }
        view.addSubview(overlay)

        pencilRecognizer.inputDelegate = self
        pencilRecognizer.delegate = self
        scrollView.addGestureRecognizer(pencilRecognizer)

        selectionDrag.addTarget(self, action: #selector(handleSelectionDrag(_:)))
        selectionDrag.maximumNumberOfTouches = 1
        selectionDrag.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        selectionDrag.delegate = self
        scrollView.addGestureRecognizer(selectionDrag)
        scrollView.panGestureRecognizer.require(toFail: selectionDrag)

        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleUndoTap))
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.addGestureRecognizer(twoFingerTap)

        let threeFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleRedoTap))
        threeFingerTap.numberOfTouchesRequired = 3
        threeFingerTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.addGestureRecognizer(threeFingerTap)
        twoFingerTap.require(toFail: threeFingerTap)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.addGestureRecognizer(doubleTap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.addGestureRecognizer(longPress)

        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        scrollView.addGestureRecognizer(hover)

        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = self
        view.addInteraction(pencilInteraction)

        editMenu = UIEditMenuInteraction(delegate: self)
        view.addInteraction(editMenu)

        textEditing = TextEditingController(host: self)

        document.addObserver(self)
        rebuildPages()
        activateTool(settings.currentTool)
        applyInputSettings()

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)),
                                               name: UIResponder.keyboardWillHideNotification, object: nil)
        editor.canvas = self
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = scrollView.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        if !didRestoreViewState {
            didRestoreViewState = true
            lastLayoutSize = size
            layoutPages()
            restoreViewState()
            return
        }
        if size != lastLayoutSize {
            // Rotation / multitasking resize: keep the same content point centered.
            let oldFit = fitWidthScale(for: lastLayoutSize)
            let wasFitWidth = abs(scrollView.zoomScale - oldFit) < 0.02
            let anchor = CGPoint(x: (scrollView.contentOffset.x + lastLayoutSize.width / 2) / scrollView.zoomScale,
                                 y: (scrollView.contentOffset.y + lastLayoutSize.height / 2) / scrollView.zoomScale)
            lastLayoutSize = size
            updateZoomLimits()
            if wasFitWidth { scrollView.zoomScale = fitWidthScale(for: size) }
            layoutPages()
            center(on: anchor)
        }
    }

    // MARK: Pages & layout

    private var contentSize: CGSize {
        let maxW = document.pages.map(\.size.width).max() ?? 612
        let totalH = document.pages.reduce(0) { $0 + $1.size.height } + pageGap * CGFloat(max(document.pages.count - 1, 0))
        return CGSize(width: maxW + 2 * pageMargin, height: totalH + 2 * pageMargin)
    }

    private func rebuildPages() {
        let ids = Set(document.pages.map(\.id))
        for (id, v) in pageViews where !ids.contains(id) {
            v.removeFromSuperview()
            pageViews[id] = nil
        }
        for page in document.pages where pageViews[page.id] == nil {
            let v = PageView(store: page, renderer: renderer) { [weak self] id, rect, gen in
                self?.tileDrawn(pageID: id, rect: rect, generation: gen)
            }
            container.addSubview(v)
            pageViews[page.id] = v
        }
        layoutPages()
        if editor.pageCount != document.pages.count { editor.pageCount = document.pages.count }
    }

    private func layoutPages() {
        let size = contentSize
        var y = pageMargin
        for page in document.pages {
            guard let v = pageViews[page.id] else { continue }
            let frame = CGRect(x: (size.width - page.size.width) / 2, y: y, width: page.size.width, height: page.size.height)
            if v.frame != frame {
                let resized = v.frame.size != frame.size
                v.frame = frame
                if resized { v.invalidateAll() }
            }
            y += page.size.height + pageGap
        }
        let z = scrollView.zoomScale
        container.bounds = CGRect(origin: .zero, size: size)
        container.center = CGPoint(x: size.width * z / 2, y: size.height * z / 2)
        scrollView.contentSize = CGSize(width: size.width * z, height: size.height * z)
        updateZoomLimits()
        centerContent()
        overlay.setNeedsDisplay()
    }

    private func fitWidthScale(for size: CGSize) -> CGFloat {
        let content = contentSize
        return max(0.05, (size.width) / max(content.width, 1))
    }

    private func updateZoomLimits() {
        let fit = fitWidthScale(for: scrollView.bounds.size)
        scrollView.minimumZoomScale = max(0.1, fit * 0.3)
        scrollView.maximumZoomScale = max(24, fit * 4)
    }

    private func centerContent() {
        let b = scrollView.bounds.size
        let c = scrollView.contentSize
        let x = max(0, (b.width - c.width) / 2)
        let y = max(0, (b.height - c.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: y, left: x, bottom: y + keyboardInset, right: x)
    }

    private func center(on contentPoint: CGPoint) {
        let z = scrollView.zoomScale
        var offset = CGPoint(x: contentPoint.x * z - scrollView.bounds.width / 2,
                             y: contentPoint.y * z - scrollView.bounds.height / 2)
        offset = clampOffset(offset)
        scrollView.contentOffset = offset
    }

    private func clampOffset(_ o: CGPoint) -> CGPoint {
        let inset = scrollView.contentInset
        let maxX = max(-inset.left, scrollView.contentSize.width - scrollView.bounds.width + inset.right)
        let maxY = max(-inset.top, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
        return CGPoint(x: o.x.clamped(-inset.left, maxX), y: o.y.clamped(-inset.top, maxY))
    }

    private func restoreViewState() {
        let state = document.viewState
        updateZoomLimits()
        if state.zoomScale > 0 {
            scrollView.zoomScale = state.zoomScale.clamped(scrollView.minimumZoomScale, scrollView.maximumZoomScale)
            layoutPages()
            let z = scrollView.zoomScale
            scrollView.contentOffset = clampOffset(CGPoint(x: state.contentOffset.x * z, y: state.contentOffset.y * z))
        } else {
            scrollView.zoomScale = fitWidthScale(for: scrollView.bounds.size)
            layoutPages()
            scrollView.contentOffset = CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top)
        }
        updateCurrentPage()
        editor.zoomPercent = Int((scrollView.zoomScale * 100).rounded())
    }

    private func saveViewState() {
        let z = scrollView.zoomScale
        document.viewState = ViewState(pageIndex: editor.currentPageIndex, zoomScale: z,
                                       contentOffset: CGPoint(x: scrollView.contentOffset.x / z, y: scrollView.contentOffset.y / z))
    }

    private var visibleContentRect: CGRect {
        scrollView.convert(scrollView.bounds, to: container)
    }

    private func updateCurrentPage() {
        let center = visibleContentRect.center
        var best = 0
        var bestD = CGFloat.greatestFiniteMagnitude
        for (i, page) in document.pages.enumerated() {
            guard let f = pageViews[page.id]?.frame else { continue }
            if f.contains(center) { best = i; break }
            let d = min(abs(center.y - f.minY), abs(center.y - f.maxY))
            if d < bestD { bestD = d; best = i }
        }
        if editor.currentPageIndex != best { editor.currentPageIndex = best }
    }

    private func pageView(near containerPoint: CGPoint) -> PageView? {
        var best: PageView?
        var bestD = CGFloat.greatestFiniteMagnitude
        for page in document.pages {
            guard let v = pageViews[page.id] else { continue }
            if v.frame.contains(containerPoint) { return v }
            let dy = max(v.frame.minY - containerPoint.y, containerPoint.y - v.frame.maxY, 0)
            let dx = max(v.frame.minX - containerPoint.x, containerPoint.x - v.frame.maxX, 0)
            let d = dx + dy
            if d < bestD { bestD = d; best = v }
        }
        return best
    }

    // MARK: Tools

    func activateTool(_ kind: ToolKind) {
        activeTool?.deactivate()
        if kind != .lasso { clearSelection() }
        if kind != .text, textEditing?.isEditing == true { endTextEditing() }
        activeKind = kind
        if let t = tools[kind] {
            activeTool = t
        } else {
            let t: CanvasTool
            switch kind {
            case .pen: t = PenTool(host: self, mode: .pen)
            case .highlighter: t = PenTool(host: self, mode: .highlighter)
            case .shapes: t = PenTool(host: self, mode: .shapes)
            case .eraser: t = EraserTool(host: self)
            case .lasso: t = LassoTool(host: self)
            case .text: t = TextTool(host: self)
            }
            tools[kind] = t
            activeTool = t
        }
        overlay.setNeedsDisplay()
    }

    func applyInputSettings() {
        pencilRecognizer.allowsFingerDrawing = settings.fingerDrawing
        scrollView.panGestureRecognizer.minimumNumberOfTouches = settings.fingerDrawing ? 2 : 1
    }

    func settingsDidChange(from old: ToolSettings) {
        if old.currentTool != settings.currentTool { activateTool(settings.currentTool) }
        if old.fingerDrawing != settings.fingerDrawing { applyInputSettings() }
        if old.text != settings.text, textEditing.isEditing { textEditing.updateStyle(settings.text) }
    }

    /// Cancels any in-flight gesture (used before undo/redo and page changes).
    func cancelInteraction() {
        activeTool?.cancelled()
        activePageID = nil
    }

    // MARK: Input conversion

    private func sample(_ t: UITouch, in view: UIView) -> InputSample {
        let isPencil = t.type == .pencil
        let force: CGFloat
        if isPencil, t.maximumPossibleForce > 0 {
            force = (t.force / t.maximumPossibleForce).clamped(0, 1)
        } else {
            force = 0.25
        }
        return InputSample(
            location: t.preciseLocation(in: view),
            force: force,
            altitude: isPencil ? t.altitudeAngle : .pi / 2,
            azimuth: isPencil ? t.azimuthAngle(in: view) : 0,
            timestamp: t.timestamp,
            estimationIndex: t.estimatedPropertiesExpectingUpdates.isEmpty ? nil : t.estimationUpdateIndex,
            isPencil: isPencil)
    }

    private func makeInput(_ touch: UITouch, event: UIEvent?, pageView: PageView) -> ToolInput {
        let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
        let predicted = event?.predictedTouches(for: touch) ?? []
        return ToolInput(pageID: pageView.pageID,
                         samples: (coalesced.isEmpty ? [touch] : coalesced).map { sample($0, in: pageView) },
                         predicted: predicted.map { sample($0, in: pageView) })
    }

    // MARK: Overlay

    private func drawOverlay(_ ctx: CGContext, _ rect: CGRect) {
        for p in pending {
            guard let page = document.page(p.pageID) else { continue }
            ctx.saveGState()
            ctx.concatenate(pageToOverlay(p.pageID))
            ctx.clip(to: page.bounds)
            renderer.draw(p.item.element, stamp: p.item.stamp, in: ctx, background: page.background)
            ctx.restoreGState()
        }
        if let pid = selection.pageID, let page = document.page(pid) {
            selection.draw(in: ctx, pageToOverlay: pageToOverlay(pid), renderer: renderer, background: page.background)
        }
        activeTool?.drawOverlay(in: ctx)
    }

    private func tileDrawn(pageID: UUID, rect: CGRect, generation: UInt64) {
        guard !pending.isEmpty else { return }
        var removed = CGRect.null
        for i in pending.indices where pending[i].pageID == pageID && generation >= pending[i].generation {
            pending[i].covered = pending[i].covered.union(rect)
        }
        let pageBounds = document.page(pageID)?.bounds ?? .null
        pending.removeAll { p in
            let needed = p.item.element.bounds.intersection(pageBounds).intersection(visibleContentRectInPage(p.pageID))
            let done = p.pageID == pageID && (needed.isNull || p.covered.contains(needed))
            if done { removed = removed.union(p.item.element.bounds.applying(pageToOverlay(p.pageID))) }
            return done
        }
        if !removed.isNull { overlay.setNeedsDisplay(removed.expanded(by: 4)) }
    }

    private func visibleContentRectInPage(_ pageID: UUID) -> CGRect {
        guard let v = pageViews[pageID] else { return .null }
        return container.convert(visibleContentRect, to: v)
    }

    private func expirePending() {
        let now = CACurrentMediaTime()
        let before = pending.count
        pending.removeAll { now - $0.created > 1.0 }
        if pending.count != before { overlay.setNeedsDisplay() }
    }

    // MARK: Gestures

    @objc private func handleUndoTap() { editor.undo() }
    @objc private func handleRedoTap() { editor.redo() }

    /// Finger double-tap: fit the tapped page to the screen. Double-tapping
    /// again (while still fitted) returns to the previous zoom and position.
    @objc private func handleDoubleTap(_ g: UITapGestureRecognizer) {
        guard let v = pageView(near: g.location(in: container)) else { return }
        if let previous = zoomBeforeFit, previous.pageID == v.pageID,
           abs(scrollView.zoomScale - fitScale(for: v.frame)) < 0.01 * scrollView.zoomScale {
            zoomBeforeFit = nil
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                self.scrollView.setZoomScale(previous.zoom, animated: false)
                self.scrollView.contentOffset = self.clampOffset(previous.offset)
            } completion: { _ in self.saveViewState() }
            return
        }
        zoomBeforeFit = (v.pageID, scrollView.zoomScale, scrollView.contentOffset)
        fit(pageView: v)
    }

    private var zoomBeforeFit: (pageID: UUID, zoom: CGFloat, offset: CGPoint)?

    /// Largest zoom at which the whole page is visible.
    private func fitScale(for pageFrame: CGRect) -> CGFloat {
        let margin: CGFloat = 12
        let avail = CGSize(width: scrollView.bounds.width - 2 * margin,
                           height: scrollView.bounds.height - keyboardInset - 2 * margin)
        let s = min(avail.width / pageFrame.width, avail.height / pageFrame.height)
        return s.clamped(scrollView.minimumZoomScale, scrollView.maximumZoomScale)
    }

    /// Zooms so the page fills the screen and centers it.
    private func fit(pageView v: PageView, animated: Bool = true) {
        let z = fitScale(for: v.frame)
        let apply = {
            self.scrollView.setZoomScale(z, animated: false)
            let offset = CGPoint(x: v.frame.midX * z - self.scrollView.bounds.width / 2,
                                 y: v.frame.midY * z - (self.scrollView.bounds.height - self.keyboardInset) / 2)
            self.scrollView.contentOffset = self.clampOffset(offset)
        }
        if animated {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: apply) { _ in
                self.updateCurrentPage()
                self.saveViewState()
            }
        } else {
            apply()
            updateCurrentPage()
            saveViewState()
        }
    }

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, Clipboard.hasContent, let v = pageView(near: g.location(in: container)) else { return }
        presentPasteMenu(at: g.location(in: v), pageID: v.pageID)
    }

    @objc private func handleHover(_ g: UIHoverGestureRecognizer) {
        switch g.state {
        case .began, .changed:
            guard let v = pageView(near: g.location(in: container)) else { return }
            activeTool?.hover(at: g.location(in: v), pageID: v.pageID)
        default:
            activeTool?.hover(at: nil, pageID: nil)
        }
    }

    @objc private func handleSelectionDrag(_ g: UIPanGestureRecognizer) {
        guard activeKind == .lasso, let pid = selection.pageID ?? activePageID, let v = pageViews[pid] else { return }
        let s = InputSample(location: g.location(in: v), force: 0.25, altitude: .pi / 2, azimuth: 0,
                            timestamp: CACurrentMediaTime(), estimationIndex: nil, isPencil: false)
        let input = ToolInput(pageID: pid, samples: [s], predicted: [], isFinger: true)
        switch g.state {
        case .began: activePageID = pid; dismissMenu(); activeTool.began(input)
        case .changed: activeTool.moved(input)
        case .ended: activeTool.ended(input); activePageID = nil
        default: activeTool.cancelled(); activePageID = nil
        }
    }

    // MARK: Keyboard

    @objc private func keyboardWillChange(_ n: Notification) {
        guard let frame = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let local = view.convert(frame, from: nil)
        keyboardInset = max(0, view.bounds.maxY - local.minY)
        centerContent()
        if textEditing.isEditing {
            let r = textEditing.textView.frame
            let visibleBottom = view.bounds.height - keyboardInset - 20
            if r.maxY > visibleBottom {
                var o = scrollView.contentOffset
                o.y += r.maxY - visibleBottom
                scrollView.setContentOffset(o, animated: true)
            }
        }
    }

    @objc private func keyboardWillHide(_ n: Notification) {
        keyboardInset = 0
        centerContent()
    }

    // MARK: Menus

    private func dismissMenu() {
        editMenu.dismissMenu()
    }

    private func selectionScreenRect() -> CGRect {
        guard let pid = selection.pageID else { return .null }
        let t = pageToOverlay(pid)
        return CGRect.bounding(selection.currentBox.corners.map { $0.applying(t) })
    }

    // MARK: Selection actions (also used by the SwiftUI chrome)

    func clearSelection() {
        guard !selection.isEmpty else { return }
        if selection.isLifted { _ = selection.settle(in: document) }
        selection.clear()
        selectionDidChange()
        overlay.setNeedsDisplay()
    }

    private var selectedElements: [CanvasElement] {
        guard let pid = selection.pageID, let page = document.page(pid) else { return [] }
        return selection.ids.compactMap { page.element($0) }
    }

    func deleteSelection() {
        guard let pid = selection.pageID, let page = document.page(pid) else { return }
        history.perform(ElementsEdit.remove(selection.ids, from: page, name: "Delete"))
        clearSelection()
    }

    func copySelection() {
        guard let pid = selection.pageID, let page = document.page(pid) else { return }
        Clipboard.copy(selectedElements, assetsURL: document.assetsURL, renderer: renderer, background: page.background)
        editor.clipboardChanged()
    }

    func cutSelection() {
        copySelection()
        deleteSelection()
    }

    func duplicateSelection() {
        guard let pid = selection.pageID, let page = document.page(pid) else { return }
        let offset = CGAffineTransform(translationX: 18, y: 18)
        let copies = selectedElements.map { $0.withNewID().transformed(by: offset) }
        guard !copies.isEmpty else { return }
        history.perform(ElementsEdit.add(copies, to: page, name: "Duplicate"))
        showPending(copies, pageID: pid)
        select(copies, pageID: pid)
    }

    func paste(at point: CGPoint? = nil, pageID: UUID? = nil) {
        guard var elements = Clipboard.paste(into: document.assetsURL), !elements.isEmpty else { return }
        let pid = pageID ?? currentPageID
        guard let page = document.page(pid) else { return }
        let bounds = elements.reduce(CGRect.null) { $0.union($1.bounds) }
        // Fit huge pastes (e.g. photos) onto the page.
        let maxSize = CGSize(width: page.size.width * 0.8, height: page.size.height * 0.8)
        let scale = min(1, maxSize.width / max(bounds.width, 1), maxSize.height / max(bounds.height, 1))
        let target = point ?? visibleCenter(in: pid)
        let t = CGAffineTransform(translationX: -bounds.midX, y: -bounds.midY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: target.x, y: target.y))
        elements = elements.map { $0.transformed(by: t) }
        history.perform(ElementsEdit.add(elements, to: page, name: "Paste"))
        showPending(elements, pageID: pid)
        editor.selectTool(.lasso)
        select(elements, pageID: pid)
    }

    func recolorSelection(_ color: RGBAColor) {
        updateSelection(name: "Change Color") { $0.supportsColor ? $0.recolored(color) : $0 }
    }

    /// Applies a per-element change to the selection as one undoable action.
    func updateSelection(name: String, _ change: (CanvasElement) -> CanvasElement) {
        guard let pid = selection.pageID, let page = document.page(pid) else { return }
        let pairs = selectedElements.map { (before: $0, after: change($0)) }
        history.perform(ElementsEdit.update(pairs, page: page, name: name))
        selection.refresh(from: page)
        selectionDidChange()
        overlay.setNeedsDisplay()
    }

    func arrangeSelection(toFront: Bool) {
        guard let pid = selection.pageID, let page = document.page(pid) else { return }
        let ordered = selection.ids.compactMap { id in page.index(of: id).map { (id, $0) } }.sorted { $0.1 < $1.1 }
        // Moves are applied in sequence; each `from` is the index at the time
        // of that move so undo (applied in reverse) restores the exact order.
        var moves: [(id: UUID, from: Int, to: Int)] = []
        for (k, entry) in ordered.enumerated() {
            if toFront {
                // Earlier moves took k elements from below this one.
                moves.append((entry.0, entry.1 - k, page.count - 1))
            } else {
                moves.append((entry.0, entry.1, k))
            }
        }
        history.perform(ReorderElementsCommand(name: toFront ? "Bring to Front" : "Send to Back", pageID: pid, moves: moves))
    }

    func select(_ elements: [CanvasElement], pageID: UUID) {
        selection.select(elements, pageID: pageID)
        selectionDidChange()
        overlay.setNeedsDisplay()
        presentSelectionMenu()
    }

    func editSelectedText() {
        guard case let .text(t)? = selectedElements.first, let pid = selection.pageID else { return }
        clearSelection()
        editor.selectTool(.text)
        beginTextEditing(t, pageID: pid, isNew: false)
    }

    // MARK: Pages / navigation (used by the SwiftUI chrome)

    var currentPageID: UUID {
        let i = editor.currentPageIndex.clamped(0, max(document.pages.count - 1, 0))
        return document.pages[i].id
    }

    private func visibleCenter(in pageID: UUID) -> CGPoint {
        guard let v = pageViews[pageID] else { return .zero }
        let c = container.convert(visibleContentRect.center, to: v)
        let b = v.bounds.insetBy(dx: 40, dy: 40)
        return CGPoint(x: c.x.clamped(b.minX, max(b.minX, b.maxX)), y: c.y.clamped(b.minY, max(b.minY, b.maxY)))
    }

    func scrollToPage(_ index: Int, animated: Bool = true) {
        guard document.pages.indices.contains(index), let v = pageViews[document.pages[index].id] else { return }
        let z = scrollView.zoomScale
        let offset = clampOffset(CGPoint(x: scrollView.contentOffset.x, y: (v.frame.minY - pageGap / 2) * z))
        scrollView.setContentOffset(offset, animated: animated)
        editor.currentPageIndex = index
    }

    func fitPage() {
        guard let v = pageViews[currentPageID] else { return }
        fit(pageView: v)
    }

    func fitWidth() {
        let fit = fitWidthScale(for: scrollView.bounds.size)
        let anchor = visibleContentRect.center
        scrollView.setZoomScale(fit, animated: false)
        center(on: CGPoint(x: contentSize.width / 2, y: anchor.y))
    }

    func setZoom(_ scale: CGFloat) {
        let anchor = visibleContentRect.center
        scrollView.setZoomScale(scale.clamped(scrollView.minimumZoomScale, scrollView.maximumZoomScale), animated: false)
        center(on: anchor)
    }

    func zoom(by factor: CGFloat) { setZoom(scrollView.zoomScale * factor) }

    // MARK: Images

    func insertImage(_ image: UIImage) {
        let pid = currentPageID
        guard let page = document.page(pid), let stored = ImageImporter.store(image, in: document.assetsURL) else { return }
        var size = stored.size
        let maxW = page.size.width * 0.6, maxH = page.size.height * 0.6
        let s = min(1, maxW / size.width, maxH / size.height)
        size = CGSize(width: size.width * s, height: size.height * s)
        let element = CanvasElement.image(ImageElement(assetName: stored.name, box: BoxGeometry(center: visibleCenter(in: pid), size: size)))
        history.perform(ElementsEdit.add([element], to: page, name: "Insert Image"))
        showPending([element], pageID: pid)
        editor.selectTool(.lasso)
        select([element], pageID: pid)
    }

    // MARK: Export

    func exportPDF() -> URL? {
        let pages = document.pages.map { $0.pageData() }
        guard let first = pages.first else { return nil }
        let name = document.title.isEmpty ? "Untitled" : document.title
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).pdf")
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: first.size))
        do {
            try pdf.writePDF(to: url) { ctx in
                for page in pages {
                    ctx.beginPage(withBounds: CGRect(origin: .zero, size: page.size), pageInfo: [:])
                    renderer.drawPage(page, in: ctx.cgContext)
                }
            }
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - ToolHost

extension CanvasViewController: ToolHost {
    var zoomScale: CGFloat { scrollView.zoomScale }

    func pageToOverlay(_ pageID: UUID) -> CGAffineTransform {
        guard let v = pageViews[pageID] else { return .identity }
        let origin = v.convert(CGPoint.zero, to: overlay)
        let z = scrollView.zoomScale
        return CGAffineTransform(a: z, b: 0, c: 0, d: z, tx: origin.x, ty: origin.y)
    }

    func invalidateOverlay(pageRect: CGRect, pageID: UUID) {
        guard !pageRect.isNull else { return }
        overlay.setNeedsDisplay(pageRect.applying(pageToOverlay(pageID)).expanded(by: 2))
    }

    func invalidateOverlayScreenRect(_ rect: CGRect) {
        guard !rect.isNull else { return }
        overlay.setNeedsDisplay(rect)
    }

    func invalidateOverlay() { overlay.setNeedsDisplay() }

    func showPending(_ elements: [CanvasElement], pageID: UUID) {
        guard let page = document.page(pageID) else { return }
        let gen = page.generation
        let now = CACurrentMediaTime()
        for e in elements {
            pending.append(Pending(pageID: pageID, item: RenderItem(element: e, stamp: page.stamp(for: e.id)),
                                   generation: gen, covered: .null, created: now))
            invalidateOverlay(pageRect: e.bounds, pageID: pageID)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) { [weak self] in self?.expirePending() }
    }

    var isEditingText: Bool { textEditing.isEditing }

    func beginTextEditing(_ element: TextElement, pageID: UUID, isNew: Bool) {
        textEditing.begin(element, pageID: pageID, isNew: isNew, in: view)
        editor.isEditingText = true
        if editor.settings.text != element.style {
            editor.settings.text = element.style
        }
    }

    func endTextEditing() {
        textEditing.end()
        editor.isEditingText = false
    }

    func selectionDidChange() {
        editor.updateSelectionSummary(selectedElements)
    }

    func presentSelectionMenu() {
        guard !selection.isEmpty else { return }
        let r = selectionScreenRect()
        guard !r.isNull else { return }
        menuContext = .selection
        editMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: CGPoint(x: r.midX, y: r.minY)))
    }

    func presentPasteMenu(at point: CGPoint, pageID: UUID) {
        menuContext = .paste(point: point, pageID: pageID)
        let screen = point.applying(pageToOverlay(pageID))
        editMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: screen))
    }
}

// MARK: - Pencil input

extension CanvasViewController: PencilInputDelegate {
    func pencilBegan(_ touch: UITouch, event: UIEvent) {
        dismissMenu()
        if textEditing.isEditing && activeKind != .text { endTextEditing() }
        guard let v = pageView(near: touch.location(in: container)) else { return }
        activePageID = v.pageID
        activeTool.began(makeInput(touch, event: event, pageView: v))
    }

    func pencilMoved(_ touch: UITouch, event: UIEvent) {
        guard let pid = activePageID, let v = pageViews[pid] else { return }
        activeTool.moved(makeInput(touch, event: event, pageView: v))
    }

    func pencilEnded(_ touch: UITouch, event: UIEvent) {
        guard let pid = activePageID, let v = pageViews[pid] else { return }
        activeTool.ended(makeInput(touch, event: event, pageView: v))
        activePageID = nil
    }

    func pencilCancelled(_ touch: UITouch) {
        activeTool.cancelled()
        activePageID = nil
    }

    func pencilEstimatesUpdated(_ touches: Set<UITouch>) {
        guard let pid = activePageID, let v = pageViews[pid] else { return }
        activeTool.updateEstimated(touches.map { t in
            var s = sample(t, in: v)
            s.estimationIndex = t.estimationUpdateIndex
            return s
        })
    }
}

// MARK: - Gesture delegate

extension CanvasViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        g === pencilRecognizer || other === pencilRecognizer
    }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard g === selectionDrag else { return true }
        guard activeKind == .lasso, let pid = selection.pageID, let v = pageViews[pid] else { return false }
        let p = g.location(in: v)
        let t = pageToOverlay(pid)
        if selection.handle(at: p.applying(t), pageToOverlay: t) != nil { return true }
        return selection.currentBox.contains(p, tolerance: 8 / max(zoomScale, 0.01))
    }
}

// MARK: - Scroll view

extension CanvasViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { container }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        lockHorizontalScrollIfPageFits()
        editor.zoomPercent = Int((scrollView.zoomScale * 100).rounded())
        overlayNeedsReposition()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        lockHorizontalScrollIfPageFits()
        updatePullToAddPage()
        updateCurrentPage()
        overlayNeedsReposition()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        saveViewState()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { saveViewState() }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard pullToAdd.isArmed else { return }
        // Released past the threshold: append a page and glide to it.
        let lastIndex = document.pages.count - 1
        editor.addPage(after: lastIndex, scroll: false)
        let newIndex = lastIndex + 1
        guard document.pages.indices.contains(newIndex), let v = pageViews[document.pages[newIndex].id] else { return }
        let z = scrollView.zoomScale
        targetContentOffset.pointee = clampOffset(CGPoint(x: targetContentOffset.pointee.x, y: (v.frame.minY - pageGap / 2) * z))
        editor.currentPageIndex = newIndex
        updatePullToAddPage()
    }

    /// Drives the "Pull to Add Page" indicator from the overscroll past the last page.
    private func updatePullToAddPage() {
        guard let last = document.pages.last, let v = pageViews[last.id] else { return }
        let maxOffsetY = max(scrollView.contentSize.height + scrollView.contentInset.bottom - scrollView.bounds.height,
                             -scrollView.contentInset.top)
        let pull = scrollView.contentOffset.y - maxOffsetY
        let pageFrame = v.convert(v.bounds, to: view)
        // Only while the user is interacting (or the bounce-back after it).
        let active = scrollView.isTracking || scrollView.isDecelerating || pull > 0
        pullToAdd.update(pull: active && !scrollView.isZooming ? pull : 0, pageBottom: pageFrame.maxY, pageFrame: pageFrame)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { saveViewState() }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { saveViewState() }

    /// When the widest page fits across the screen (e.g. after a double-tap
    /// fit), there is nothing to see sideways: keep the pages centered and
    /// don't let the canvas drift or bounce horizontally.
    private func lockHorizontalScrollIfPageFits() {
        let z = scrollView.zoomScale
        let pageWidth = document.pages.map(\.size.width).max() ?? 0
        let fits = pageWidth * z <= scrollView.bounds.width + 0.5
        scrollView.showsHorizontalScrollIndicator = !fits
        guard fits else { return }
        let target = scrollView.contentSize.width <= scrollView.bounds.width
            ? -scrollView.contentInset.left
            : (scrollView.contentSize.width - scrollView.bounds.width) / 2
        if abs(scrollView.contentOffset.x - target) > 0.01 {
            scrollView.contentOffset.x = target
        }
    }

    private func overlayNeedsReposition() {
        if !pending.isEmpty || !selection.isEmpty || activePageID != nil {
            overlay.setNeedsDisplay()
        }
        if textEditing.isEditing { textEditing.layout() }
        if !selection.isEmpty { dismissMenu() }
    }
}

// MARK: - Document changes

extension CanvasViewController: DocumentObserver {
    func document(_ document: DocumentModel, didChange change: DocumentChange) {
        switch change {
        case let .elements(pageID, rect):
            pageViews[pageID]?.invalidate(rect)
        case let .pageSettings(pageID):
            pageViews[pageID]?.invalidateAll()
        case .pageStructure:
            rebuildPages()
            for v in pageViews.values { v.invalidateAll() }
            updateCurrentPage()
        case .metadata:
            break
        }
    }
}

// MARK: - Apple Pencil double tap

extension CanvasViewController: UIPencilInteractionDelegate {
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        switch UIPencilInteraction.preferredTapAction {
        case .switchEraser: editor.toggleEraser()
        case .switchPrevious: editor.switchToPreviousTool()
        case .showColorPalette: editor.showToolOptions.toggle()
        default: break
        }
    }
}

// MARK: - Edit menu

extension CanvasViewController: UIEditMenuInteractionDelegate {
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        switch menuContext {
        case let .paste(point, pageID):
            return UIMenu(children: [
                UIAction(title: "Paste", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in
                    self?.paste(at: point, pageID: pageID)
                },
            ])
        case .selection:
            guard !selection.isEmpty else { return nil }
            let elements = selectedElements
            var items: [UIMenuElement] = [
                UIAction(title: "Cut", image: UIImage(systemName: "scissors")) { [weak self] _ in self?.cutSelection() },
                UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in self?.copySelection() },
                UIAction(title: "Duplicate", image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in self?.duplicateSelection() },
                UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.deleteSelection() },
            ]
            if elements.contains(where: \.supportsColor) {
                let colors = RGBAColor.inkPalette.map { c in
                    UIAction(title: "", image: UIImage(systemName: "circle.fill")?.withTintColor(c.uiColor, renderingMode: .alwaysOriginal)) { [weak self] _ in
                        self?.recolorSelection(c)
                    }
                }
                items.append(UIMenu(title: "Color", image: UIImage(systemName: "paintpalette"), options: .displayInline, children: colors))
            }
            items.append(UIAction(title: "Style…", image: UIImage(systemName: "slider.horizontal.3")) { [weak self] _ in
                self?.editor.showSelectionInspector = true
            })
            if elements.count == 1, case .text = elements[0] {
                items.append(UIAction(title: "Edit Text", image: UIImage(systemName: "character.cursor.ibeam")) { [weak self] _ in
                    self?.editSelectedText()
                })
            }
            items.append(UIMenu(title: "Arrange", image: UIImage(systemName: "square.3.layers.3d"), children: [
                UIAction(title: "Bring to Front", image: UIImage(systemName: "square.3.layers.3d.top.filled")) { [weak self] _ in self?.arrangeSelection(toFront: true) },
                UIAction(title: "Send to Back", image: UIImage(systemName: "square.3.layers.3d.bottom.filled")) { [weak self] _ in self?.arrangeSelection(toFront: false) },
            ]))
            return UIMenu(children: items)
        }
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        switch menuContext {
        case .selection:
            let r = selectionScreenRect()
            return r.isNull ? .zero : r.expanded(by: 30)
        case let .paste(point, pageID):
            let p = point.applying(pageToOverlay(pageID))
            return CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2)
        }
    }
}
