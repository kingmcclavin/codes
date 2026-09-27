import CoreGraphics
import Foundation

/// Turns a recognized scribble into an erase command.
@MainActor
enum ScribbleEraser {
    /// Returns nil when the scribble doesn't meaningfully cover existing
    /// content – in that case the scribble is kept as ink.
    static func command(for scribble: [CGPoint], on page: PageStore, mode: ScribbleEraseMode, tolerance: CGFloat) -> EditCommand? {
        let region = CGRect.bounding(scribble)
        let candidates = page.elements(in: region.expanded(by: tolerance))
        let hit = candidates.filter { $0.intersects(path: scribble, radius: tolerance) }
        guard !hit.isEmpty else { return nil }

        // Coverage guard: a real scribble lies mostly on top of content.
        let samples = Geometry.resample(scribble, spacing: max(2, region.diagonal / 60))
        let near = samples.filter { p in hit.contains { $0.hitTest(p, tolerance: tolerance * 1.5) } }.count
        guard Double(near) / Double(max(samples.count, 1)) >= 0.2 else { return nil }

        switch mode {
        case .strokes:
            return removal(hit.map(\.id), page: page)
        case .objects:
            return removal(expandToObjects(hit, page: page, region: region), page: page)
        case .region:
            return regionErase(scribble, candidates: candidates, page: page)
        }
    }

    private static func removal(_ ids: [UUID], page: PageStore) -> EditCommand? {
        let edit = ElementsEdit.remove(ids, from: page, name: "Scribble Erase")
        return edit.isEmpty ? nil : edit
    }

    /// Grows the hit set to whole objects: elements that touch each other
    /// (e.g. the letters of a word) inside the neighbourhood of the scribble.
    private static func expandToObjects(_ hit: [CanvasElement], page: PageStore, region: CGRect) -> [UUID] {
        let neighbourhood = region.expanded(by: max(12, region.diagonal * 0.3))
        let pool = page.elements(in: neighbourhood)
        var selected = Set(hit.map(\.id))
        var queue = hit
        let gap: CGFloat = 3
        while let e = queue.popLast() {
            let eb = e.bounds.expanded(by: gap)
            for o in pool where !selected.contains(o.id) && neighbourhood.contains(o.bounds.center) {
                guard o.bounds.intersects(eb) else { continue }
                // Require actual proximity for strokes, not just overlapping boxes.
                let close: Bool
                if case .stroke = o, case .stroke = e {
                    close = o.samplePoints.contains { e.hitTest($0, tolerance: gap + 2) }
                        || e.samplePoints.contains { o.hitTest($0, tolerance: gap + 2) }
                } else {
                    close = true
                }
                if close {
                    selected.insert(o.id)
                    queue.append(o)
                }
            }
        }
        return Array(selected)
    }

    /// Erases everything inside the scribble's hull; strokes crossing the
    /// boundary are split so only the covered part disappears.
    private static func regionErase(_ scribble: [CGPoint], candidates: [CanvasElement], page: PageStore) -> EditCommand? {
        let hull = Geometry.convexHull(scribble)
        guard hull.count >= 3 else { return nil }
        // Process top-down in descending z so earlier edits don't shift later indices.
        let indexed = candidates.compactMap { e -> (Int, CanvasElement)? in
            page.index(of: e.id).map { ($0, e) }
        }.sorted { $0.0 > $1.0 }

        var edits: [EditCommand] = []
        for (index, element) in indexed {
            switch element {
            case let .stroke(s):
                guard let pieces = ErasureEngine.erase(s, inside: hull) else { continue }
                edits.append(ElementsEdit.replace(element, at: index, with: pieces.map { .stroke($0) }, page: page, name: "Scribble Erase"))
            default:
                let inside = element.samplePoints.filter { Geometry.polygonContains(hull, $0) }.count
                if Double(inside) / Double(max(element.samplePoints.count, 1)) >= 0.5 {
                    edits.append(ElementsEdit(name: "Scribble Erase", pageID: page.id,
                                              removed: [IndexedElement(index: index, element: element)]))
                }
            }
        }
        return edits.isEmpty ? nil : CompositeCommand(name: "Scribble Erase", commands: edits)
    }
}
