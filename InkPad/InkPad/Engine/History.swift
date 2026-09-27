import Foundation

/// Unlimited linear undo/redo of `EditCommand`s.
@MainActor
final class History {
    private(set) var undoStack: [EditCommand] = []
    private(set) var redoStack: [EditCommand] = []
    private unowned let document: DocumentModel

    /// Invoked after any change to the stacks.
    var onChange: (() -> Void)?

    init(document: DocumentModel) {
        self.document = document
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoActionName: String? { undoStack.last?.name }
    var redoActionName: String? { redoStack.last?.name }

    /// Applies a command and records it.
    func perform(_ command: EditCommand) {
        command.apply(to: document)
        record(command)
    }

    /// Records a command whose effect has already been applied (used by tools
    /// that mutate incrementally, such as the eraser).
    func record(_ command: EditCommand) {
        if let edit = command as? ElementsEdit, edit.isEmpty { return }
        if let composite = command as? CompositeCommand, composite.commands.isEmpty { return }
        undoStack.append(command)
        redoStack.removeAll()
        onChange?()
    }

    @discardableResult
    func undo() -> EditCommand? {
        guard let c = undoStack.popLast() else { return nil }
        c.revert(on: document)
        redoStack.append(c)
        onChange?()
        return c
    }

    @discardableResult
    func redo() -> EditCommand? {
        guard let c = redoStack.popLast() else { return nil }
        c.apply(to: document)
        undoStack.append(c)
        onChange?()
        return c
    }

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        onChange?()
    }
}
