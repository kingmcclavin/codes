import CoreGraphics
import Foundation

/// Uniform-grid spatial index. Lets rendering, hit testing and erasing touch
/// only the elements near a region, so cost stays flat as a page fills up.
struct SpatialGrid {
    struct Cell: Hashable {
        var x: Int32
        var y: Int32
    }

    let cellSize: CGFloat
    private var cells: [Cell: Set<UUID>] = [:]
    private var membership: [UUID: [Cell]] = [:]

    init(cellSize: CGFloat = 128) {
        self.cellSize = cellSize
    }

    private func cellRange(_ rect: CGRect) -> (ClosedRange<Int32>, ClosedRange<Int32>)? {
        guard !rect.isNull, !rect.isInfinite, rect.minX.isFinite, rect.minY.isFinite else { return nil }
        let x0 = Int32(clamping: Int(floor(rect.minX / cellSize)))
        let x1 = Int32(clamping: Int(floor(rect.maxX / cellSize)))
        let y0 = Int32(clamping: Int(floor(rect.minY / cellSize)))
        let y1 = Int32(clamping: Int(floor(rect.maxY / cellSize)))
        return (x0...max(x0, x1), y0...max(y0, y1))
    }

    mutating func insert(_ id: UUID, bounds: CGRect) {
        guard let (xs, ys) = cellRange(bounds) else { return }
        var list: [Cell] = []
        list.reserveCapacity(xs.count * ys.count)
        for x in xs {
            for y in ys {
                let cell = Cell(x: x, y: y)
                cells[cell, default: []].insert(id)
                list.append(cell)
            }
        }
        membership[id] = list
    }

    mutating func remove(_ id: UUID) {
        guard let list = membership.removeValue(forKey: id) else { return }
        for cell in list {
            cells[cell]?.remove(id)
            if cells[cell]?.isEmpty == true { cells[cell] = nil }
        }
    }

    mutating func update(_ id: UUID, bounds: CGRect) {
        remove(id)
        insert(id, bounds: bounds)
    }

    mutating func removeAll() {
        cells.removeAll()
        membership.removeAll()
    }

    func query(_ rect: CGRect) -> Set<UUID> {
        guard let (xs, ys) = cellRange(rect) else { return [] }
        var result = Set<UUID>()
        for x in xs {
            for y in ys {
                if let ids = cells[Cell(x: x, y: y)] { result.formUnion(ids) }
            }
        }
        return result
    }
}
