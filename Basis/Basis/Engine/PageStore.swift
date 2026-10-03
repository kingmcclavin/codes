import CoreGraphics
import Foundation

/// Element handed to the renderer. `stamp` changes whenever the element's
/// content changes and keys the render cache.
struct RenderItem {
    let element: CanvasElement
    let stamp: UInt64
}

/// Live, thread-safe storage for one page.
///
/// Mutations happen on the main thread (through `DocumentModel`); the tiled
/// page layers read from background threads. A lock guards all state and is
/// only held for short copies – never while drawing.
final class PageStore: @unchecked Sendable {
    let id: UUID

    private let lock = NSLock()
    private var _size: CGSize
    private var _background: PageBackground
    private var order: [UUID] = []
    private var elements: [UUID: CanvasElement] = [:]
    private var stamps: [UUID: UInt64] = [:]
    private var zIndex: [UUID: Int] = [:]
    private var zIndexValid = true
    private var grid = SpatialGrid()
    private var hidden: Set<UUID> = []
    private var nextStamp: UInt64 = 1
    private var _generation: UInt64 = 0

    init(data: PageData) {
        id = data.id
        _size = data.size
        _background = data.background
        for e in data.elements { appendUnlocked(e) }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: Properties

    var size: CGSize {
        get { withLock { _size } }
        set { withLock { _size = newValue; _generation += 1 } }
    }

    var background: PageBackground {
        get { withLock { _background } }
        set { withLock { _background = newValue; _generation += 1 } }
    }

    var bounds: CGRect { CGRect(origin: .zero, size: size) }

    /// Incremented on every mutation; lets the canvas know when a tile drawn
    /// after a commit reflects that commit.
    var generation: UInt64 { withLock { _generation } }

    var count: Int { withLock { order.count } }

    var allElements: [CanvasElement] {
        withLock { order.compactMap { elements[$0] } }
    }

    func element(_ id: UUID) -> CanvasElement? { withLock { elements[id] } }

    func stamp(for id: UUID) -> UInt64 { withLock { stamps[id] ?? 0 } }

    func index(of id: UUID) -> Int? {
        withLock {
            rebuildZIndexIfNeeded()
            return zIndex[id]
        }
    }

    func pageData() -> PageData {
        withLock {
            PageData(id: id, size: _size, background: _background, elements: order.compactMap { elements[$0] })
        }
    }

    // MARK: Mutation (main thread)

    private func appendUnlocked(_ e: CanvasElement) {
        order.append(e.id)
        elements[e.id] = e
        stamps[e.id] = nextStamp; nextStamp += 1
        if zIndexValid { zIndex[e.id] = order.count - 1 }
        grid.insert(e.id, bounds: e.bounds)
        _generation += 1
    }

    func insert(_ e: CanvasElement, at index: Int? = nil) {
        withLock {
            guard elements[e.id] == nil else { return }
            let i = (index ?? order.count).clamped(0, order.count)
            if i == order.count {
                appendUnlocked(e)
                return
            }
            order.insert(e.id, at: i)
            elements[e.id] = e
            stamps[e.id] = nextStamp; nextStamp += 1
            zIndexValid = false
            grid.insert(e.id, bounds: e.bounds)
            _generation += 1
        }
    }

    @discardableResult
    func remove(_ id: UUID) -> (index: Int, element: CanvasElement)? {
        withLock {
            guard let e = elements[id] else { return nil }
            rebuildZIndexIfNeeded()
            guard let i = zIndex[id] else { return nil }
            order.remove(at: i)
            elements[id] = nil
            stamps[id] = nil
            zIndex[id] = nil
            if i != order.count { zIndexValid = false }
            grid.remove(id)
            hidden.remove(id)
            _generation += 1
            return (i, e)
        }
    }

    /// Replaces an element with the same id. Returns the previous value.
    @discardableResult
    func replace(_ e: CanvasElement) -> CanvasElement? {
        withLock {
            guard let old = elements[e.id] else { return nil }
            elements[e.id] = e
            stamps[e.id] = nextStamp; nextStamp += 1
            grid.update(e.id, bounds: e.bounds)
            _generation += 1
            return old
        }
    }

    /// Moves an element to a new z position.
    func move(_ id: UUID, to index: Int) {
        withLock {
            rebuildZIndexIfNeeded()
            guard let i = zIndex[id] else { return }
            order.remove(at: i)
            order.insert(id, at: index.clamped(0, order.count))
            zIndexValid = false
            _generation += 1
        }
    }

    // MARK: Hidden elements (being edited / dragged in the overlay)

    func setHidden(_ ids: Set<UUID>) {
        withLock { hidden = ids; _generation += 1 }
    }

    var hiddenIDs: Set<UUID> { withLock { hidden } }

    // MARK: Queries (any thread)

    private func rebuildZIndexIfNeeded() {
        guard !zIndexValid else { return }
        zIndex.removeAll(keepingCapacity: true)
        for (i, id) in order.enumerated() { zIndex[id] = i }
        zIndexValid = true
    }

    /// Visible elements whose bounds intersect `rect`, bottom-to-top.
    func renderItems(in rect: CGRect) -> [RenderItem] {
        withLock {
            rebuildZIndexIfNeeded()
            let ids = grid.query(rect)
            var items: [(Int, RenderItem)] = []
            items.reserveCapacity(ids.count)
            for id in ids where !hidden.contains(id) {
                guard let e = elements[id], e.bounds.intersects(rect) else { continue }
                items.append((zIndex[id] ?? 0, RenderItem(element: e, stamp: stamps[id] ?? 0)))
            }
            items.sort { $0.0 < $1.0 }
            return items.map(\.1)
        }
    }

    /// Elements (including hidden ones) whose bounds intersect `rect`, bottom-to-top.
    func elements(in rect: CGRect) -> [CanvasElement] {
        withLock {
            rebuildZIndexIfNeeded()
            let ids = grid.query(rect)
            return ids.compactMap { id -> (Int, CanvasElement)? in
                guard let e = elements[id], e.bounds.intersects(rect) else { return nil }
                return (zIndex[id] ?? 0, e)
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
        }
    }

    /// Topmost element under a point.
    func topElement(at p: CGPoint, tolerance: CGFloat) -> CanvasElement? {
        elements(in: CGRect(x: p.x, y: p.y, width: 0, height: 0).expanded(by: tolerance + 2))
            .last { $0.hitTest(p, tolerance: tolerance) }
    }
}
