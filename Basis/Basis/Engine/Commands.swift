import CoreGraphics
import Foundation

/// A reversible, user-meaningful action. Every change a user makes to a
/// document is expressed as a command so undo/redo works uniformly across tools.
@MainActor
protocol EditCommand {
    var name: String { get }
    func apply(to document: DocumentModel)
    func revert(on document: DocumentModel)
}

struct IndexedElement {
    var index: Int
    var element: CanvasElement
}

/// General element edit on one page: removals, insertions and in-place updates.
///
/// * `removed` indices refer to the page *before* the edit.
/// * `inserted` indices refer to the page *after* the edit.
struct ElementsEdit: EditCommand {
    var name: String
    let pageID: UUID
    var removed: [IndexedElement] = []
    var inserted: [IndexedElement] = []
    var updated: [(before: CanvasElement, after: CanvasElement)] = []

    var isEmpty: Bool { removed.isEmpty && inserted.isEmpty && updated.isEmpty }

    func apply(to d: DocumentModel) {
        for r in removed.sorted(by: { $0.index > $1.index }) { d.removeElement(r.element.id, page: pageID) }
        for i in inserted.sorted(by: { $0.index < $1.index }) { d.insertElement(i.element, at: i.index, page: pageID) }
        for u in updated { d.replaceElement(u.after, page: pageID) }
    }

    func revert(on d: DocumentModel) {
        for u in updated.reversed() { d.replaceElement(u.before, page: pageID) }
        for i in inserted { d.removeElement(i.element.id, page: pageID) }
        for r in removed.sorted(by: { $0.index < $1.index }) { d.insertElement(r.element, at: r.index, page: pageID) }
    }

    // Convenience constructors

    static func add(_ elements: [CanvasElement], to page: PageStore, name: String) -> ElementsEdit {
        let base = page.count
        return ElementsEdit(name: name, pageID: page.id,
                            inserted: elements.enumerated().map { IndexedElement(index: base + $0.offset, element: $0.element) })
    }

    static func remove(_ ids: [UUID], from page: PageStore, name: String) -> ElementsEdit {
        let removed = ids.compactMap { id -> IndexedElement? in
            guard let e = page.element(id), let i = page.index(of: id) else { return nil }
            return IndexedElement(index: i, element: e)
        }
        return ElementsEdit(name: name, pageID: page.id, removed: removed)
    }

    static func update(_ pairs: [(before: CanvasElement, after: CanvasElement)], page: PageStore, name: String) -> ElementsEdit {
        ElementsEdit(name: name, pageID: page.id, updated: pairs)
    }

    /// Replaces one element by several (e.g. a stroke split by the eraser) at the same z position.
    static func replace(_ original: CanvasElement, at index: Int, with pieces: [CanvasElement], page: PageStore, name: String) -> ElementsEdit {
        ElementsEdit(name: name, pageID: page.id,
                     removed: [IndexedElement(index: index, element: original)],
                     inserted: pieces.enumerated().map { IndexedElement(index: index + $0.offset, element: $0.element) })
    }
}

/// Changes z-order of elements.
struct ReorderElementsCommand: EditCommand {
    var name: String
    let pageID: UUID
    /// (id, old index, new index), applied in order.
    var moves: [(id: UUID, from: Int, to: Int)]

    func apply(to d: DocumentModel) {
        for m in moves { d.moveElement(m.id, to: m.to, page: pageID) }
    }

    func revert(on d: DocumentModel) {
        for m in moves.reversed() { d.moveElement(m.id, to: m.from, page: pageID) }
    }
}

/// Several commands performed as one user action.
struct CompositeCommand: EditCommand {
    var name: String
    var commands: [EditCommand]

    func apply(to d: DocumentModel) { commands.forEach { $0.apply(to: d) } }
    func revert(on d: DocumentModel) { commands.reversed().forEach { $0.revert(on: d) } }
}

struct InsertPageCommand: EditCommand {
    var name = "Add Page"
    let page: PageData
    let index: Int

    func apply(to d: DocumentModel) { d.insertPage(page, at: index) }
    func revert(on d: DocumentModel) {
        if let i = d.pageIndex(page.id) { d.removePage(at: i) }
    }
}

struct DeletePageCommand: EditCommand {
    var name = "Delete Page"
    let page: PageData
    let index: Int

    func apply(to d: DocumentModel) {
        if let i = d.pageIndex(page.id) { d.removePage(at: i) }
    }
    func revert(on d: DocumentModel) { d.insertPage(page, at: index) }
}

struct MovePageCommand: EditCommand {
    var name = "Move Page"
    let from: Int
    let to: Int

    func apply(to d: DocumentModel) { d.movePage(from: from, to: to) }
    func revert(on d: DocumentModel) { d.movePage(from: to, to: from) }
}

struct PageSettingsCommand: EditCommand {
    var name = "Page Settings"
    struct Settings { var size: CGSize; var background: PageBackground }
    /// Per page: before / after.
    var changes: [(pageID: UUID, before: Settings, after: Settings)]

    func apply(to d: DocumentModel) {
        for c in changes { d.setPageSettings(c.pageID, size: c.after.size, background: c.after.background) }
    }
    func revert(on d: DocumentModel) {
        for c in changes { d.setPageSettings(c.pageID, size: c.before.size, background: c.before.background) }
    }
}
