import SwiftUI
import UIKit

/// Summary of the current selection for the SwiftUI chrome.
struct SelectionSummary: Equatable {
    var count: Int
    var hasInk: Bool
    var hasShapes: Bool
    var hasText: Bool
    var hasImages: Bool
    var color: RGBAColor?
    var lineWidth: CGFloat?
    var fill: RGBAColor?
    var hasFillableShapes: Bool
    var hasLines: Bool
    var arrows: ArrowHeads?
    var lineStyle: LineStyle?
    var opacity: CGFloat?
}

/// Opens the calculation sheet: a new card (`element == nil`) or an existing one.
struct CalculationEditRequest: Identifiable {
    let id = UUID()
    var block: CalculationBlock
    var element: TextElement?
    var pageID: UUID?
    /// Where a new card goes (its top-left corner); nil = middle of the screen.
    var placement: CardPlacement?
}

struct CardPlacement {
    var pageID: UUID
    var topLeft: CGPoint
}

/// Bridges the document/engine and the SwiftUI interface.
@MainActor
final class EditorModel: ObservableObject {
    let document: DocumentModel
    let history: History
    let autosave: AutosaveController
    weak var canvas: CanvasViewController?

    @Published var settings: ToolSettings {
        didSet {
            guard settings != oldValue else { return }
            document.toolSettings = settings
            canvas?.settingsDidChange(from: oldValue)
        }
    }
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var currentPageIndex = 0
    @Published var pageCount = 1
    @Published var zoomPercent = 100
    @Published private(set) var selection: SelectionSummary?
    @Published var isEditingText = false
    @Published private(set) var clipboardHasContent = false
    @Published var title: String { didSet { if title != oldValue { document.title = title } } }

    // Sheets & popovers
    @Published var showPageManager = false
    @Published var showPageSettings = false
    @Published var showImagePicker = false
    @Published var showSelectionInspector = false
    @Published var showToolOptions = false
    @Published var shareURL: URL?
    @Published var showPDFImporter = false
    @Published var importError: String?
    @Published var calculationRequest: CalculationEditRequest?
    /// Short message shown in an alert (e.g. handwriting not recognized).
    @Published var notice: String?
    @Published var isRecognizing = false

    private var previousTool: ToolKind = .pen
    private var observers: [NSObjectProtocol] = []

    init(document: DocumentModel, store: DocumentStore = .shared) {
        self.document = document
        self.history = History(document: document)
        self.autosave = AutosaveController(document: document, packageURL: store.packageURL(document.id))
        self.settings = document.toolSettings
        self.title = document.title
        self.currentPageIndex = document.viewState.pageIndex
        self.pageCount = document.pages.count

        history.onChange = { [weak self] in self?.refreshHistoryState() }
        document.onDirty = { [weak self] in self?.autosave.scheduleSave() }
        clipboardHasContent = Clipboard.hasContent

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        })
        observers.append(nc.addObserver(forName: UIPasteboard.changedNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.clipboardChanged() }
        })
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    private func refreshHistoryState() {
        canUndo = history.canUndo
        canRedo = history.canRedo
        extendPagesIfNeeded()
    }

    private var extending = false
    static let maxPageLength: CGFloat = 14_400

    /// Endless pages: grow a page when content gets close to its bottom edge.
    /// Not an undo step (shrinking back would hide nothing useful).
    private func extendPagesIfNeeded() {
        guard !extending else { return }
        extending = true
        defer { extending = false }
        for page in document.pages where page.background.autoExtends == true {
            let size = page.size
            let content = page.allElements.reduce(CGRect.null) { $0.union($1.bounds) }
            guard !content.isNull else { continue }
            var grown = size
            // Down, like an endless scroll…
            if content.maxY > size.height - 300, size.height < Self.maxPageLength {
                grown.height = min(Self.maxPageLength, max(size.height + 800, content.maxY + 600))
            }
            // …and to the right, like a whiteboard.
            if content.maxX > size.width - 200, size.width < Self.maxPageLength {
                grown.width = min(Self.maxPageLength, max(size.width + 600, content.maxX + 400))
            }
            if grown != size {
                document.growPage(page.id, to: grown)
            }
        }
    }

    // MARK: Sections

    struct SectionInfo: Identifiable, Equatable {
        var title: String
        var start: Int
        var id: Int { start }
    }

    /// Sections in page order (a section runs until the next one starts).
    var sections: [SectionInfo] {
        document.pages.enumerated().compactMap { i, p in
            guard let t = p.background.section, !t.isEmpty else { return nil }
            return SectionInfo(title: t, start: i)
        }
    }

    func section(containing index: Int) -> SectionInfo? {
        sections.last { $0.start <= index }
    }

    /// Starts (or renames, or with nil removes) a section at a page.
    func setSection(_ title: String?, at index: Int) {
        guard document.pages.indices.contains(index) else { return }
        let page = document.pages[index]
        var bg = page.background
        let t = title?.trimmingCharacters(in: .whitespaces)
        bg.section = (t?.isEmpty ?? true) ? nil : t
        guard bg != page.background else { return }
        history.perform(PageSettingsCommand(name: bg.section == nil ? "Remove Section" : "Section", changes: [
            (pageID: page.id, before: PageSettingsCommand.Settings(size: page.size, background: page.background),
             after: PageSettingsCommand.Settings(size: page.size, background: bg)),
        ]))
        objectWillChange.send()
    }

    /// Writes everything to disk synchronously (backgrounding / closing).
    func flush() {
        if isEditingText { canvas?.endTextEditing() }
        autosave.saveNow(wait: true)
    }

    // MARK: Tools

    var tool: ToolKind { settings.currentTool }

    func selectTool(_ kind: ToolKind) {
        guard kind != settings.currentTool else {
            if kind != .lasso { showToolOptions.toggle() }
            return
        }
        previousTool = settings.currentTool
        settings.currentTool = kind
    }

    func toggleEraser() {
        selectTool(settings.currentTool == .eraser ? previousTool : .eraser)
    }

    func switchToPreviousTool() {
        selectTool(previousTool)
    }

    /// Style of the active inking tool (pen or highlighter).
    var activeInkStyle: StrokeStyle {
        get { settings.currentTool == .highlighter ? settings.highlighter : settings.pen }
        set {
            if settings.currentTool == .highlighter { settings.highlighter = newValue } else { settings.pen = newValue }
        }
    }

    func useColor(_ c: RGBAColor) {
        AppPreferences.shared.noteColorUsed(c)
        switch settings.currentTool {
        case .highlighter: settings.highlighter.color = c
        case .shapes: settings.shape.strokeColor = c
        case .text: settings.text.color = c
        case .lasso: canvas?.recolorSelection(c)
        default: settings.pen.color = c
        }
    }

    var currentColor: RGBAColor {
        switch settings.currentTool {
        case .highlighter: return settings.highlighter.color
        case .shapes: return settings.shape.strokeColor
        case .text: return settings.text.color
        case .lasso: return selection?.color ?? settings.pen.color
        default: return settings.pen.color
        }
    }

    // MARK: History

    func undo() {
        canvas?.cancelInteraction()
        if isEditingText { canvas?.endTextEditing() }
        canvas?.clearSelection()
        history.undo()
    }

    func redo() {
        canvas?.cancelInteraction()
        if isEditingText { canvas?.endTextEditing() }
        canvas?.clearSelection()
        history.redo()
    }

    // MARK: Selection

    func updateSelectionSummary(_ elements: [CanvasElement]) {
        guard !elements.isEmpty else {
            selection = nil
            showSelectionInspector = false
            return
        }
        var s = SelectionSummary(count: elements.count, hasInk: false, hasShapes: false, hasText: false, hasImages: false,
                                 color: nil, lineWidth: nil, fill: nil, hasFillableShapes: false, hasLines: false,
                                 arrows: nil, lineStyle: nil, opacity: nil)
        for e in elements {
            switch e {
            case let .stroke(st):
                s.hasInk = true
                s.lineWidth = s.lineWidth ?? st.style.width
                s.opacity = s.opacity ?? st.style.opacity
                s.lineStyle = s.lineStyle ?? st.style.lineStyle
            case let .shape(sh):
                s.hasShapes = true
                s.lineWidth = s.lineWidth ?? sh.style.lineWidth
                s.opacity = s.opacity ?? sh.style.opacity
                s.lineStyle = s.lineStyle ?? sh.style.lineStyle
                if sh.geometry.isClosed { s.hasFillableShapes = true; s.fill = s.fill ?? sh.style.fillColor }
                if case .line = sh.geometry { s.hasLines = true; s.arrows = s.arrows ?? sh.arrows }
            case .text: s.hasText = true
            case let .image(img):
                s.hasImages = true
                s.opacity = s.opacity ?? img.opacity
            }
            s.color = s.color ?? e.primaryColor
        }
        selection = s
    }

    func applyToSelection(_ name: String, _ change: @escaping (CanvasElement) -> CanvasElement) {
        canvas?.updateSelection(name: name, change)
    }

    func clipboardChanged() {
        clipboardHasContent = Clipboard.hasContent
    }

    // MARK: Pages

    private func blankPage(like index: Int) -> PageData {
        let ref = document.pages[index.clamped(0, document.pages.count - 1)]
        var background = ref.background
        background.pdf = nil   // a new page after a PDF page is blank paper
        background.section = nil
        return PageData(size: ref.size, background: background)
    }

    func addPage(after index: Int? = nil, scroll: Bool = true) {
        let i = (index ?? currentPageIndex).clamped(0, document.pages.count - 1)
        history.perform(InsertPageCommand(page: blankPage(like: i), index: i + 1))
        pageCount = document.pages.count
        if scroll { canvas?.scrollToPage(i + 1) }
    }

    /// Inserts every page of a PDF after the current page (one undo step).
    func importPDF(_ url: URL) {
        do {
            let pages = try PDFImporter.pages(from: url, into: document.assetsURL)
            let start = currentPageIndex.clamped(0, document.pages.count - 1) + 1
            let commands: [EditCommand] = pages.enumerated().map { offset, page in
                InsertPageCommand(name: "Import PDF", page: page, index: start + offset)
            }
            history.perform(CompositeCommand(name: "Import PDF", commands: commands))
            pageCount = document.pages.count
            canvas?.scrollToPage(start)
        } catch {
            importError = error.localizedDescription
        }
    }

    func duplicatePage(at index: Int) {
        guard document.pages.indices.contains(index) else { return }
        var data = document.pages[index].pageData()
        data.id = UUID()
        data.elements = data.elements.map { $0.withNewID() }
        data.background.section = nil
        history.perform(InsertPageCommand(name: "Duplicate Page", page: data, index: index + 1))
        pageCount = document.pages.count
    }

    func deletePage(at index: Int) {
        guard document.pages.count > 1, document.pages.indices.contains(index) else { return }
        canvas?.clearSelection()
        history.perform(DeletePageCommand(page: document.pages[index].pageData(), index: index))
        pageCount = document.pages.count
        currentPageIndex = min(currentPageIndex, pageCount - 1)
    }

    func movePage(from: Int, to: Int) {
        guard from != to else { return }
        history.perform(MovePageCommand(from: from, to: to))
    }

    func goToPage(_ index: Int) {
        canvas?.scrollToPage(index)
    }

    func applyPageSettings(size: CGSize, background: PageBackground, toAllPages: Bool) {
        let targets = toAllPages ? document.pages : [document.pages[currentPageIndex.clamped(0, document.pages.count - 1)]]
        let changes = targets.map { p -> (pageID: UUID, before: PageSettingsCommand.Settings, after: PageSettingsCommand.Settings) in
            var after = PageSettingsCommand.Settings(size: size, background: background)
            after.background.section = p.background.section
            if let pdf = p.background.pdf {
                // Imported PDF pages keep their content and size.
                after.size = p.size
                after.background.pdf = pdf
            }
            return (p.id, PageSettingsCommand.Settings(size: p.size, background: p.background), after)
        }
        history.perform(PageSettingsCommand(changes: changes))
    }

    var currentPageSize: CGSize { document.pages[currentPageIndex.clamped(0, document.pages.count - 1)].size }
    var currentPageBackground: PageBackground { document.pages[currentPageIndex.clamped(0, document.pages.count - 1)].background }

    // MARK: Misc

    func exportPDF() {
        flush()
        shareURL = canvas?.exportPDF()
    }

    // MARK: Calculations

    func newCalculation(_ block: CalculationBlock = .expression("")) {
        calculationRequest = CalculationEditRequest(block: block)
    }

    func commitCalculation(_ request: CalculationEditRequest, block: CalculationBlock, text: String) {
        if let element = request.element, let pageID = request.pageID {
            canvas?.updateCalculation(element, pageID: pageID, block: block, text: text)
        } else {
            canvas?.insertCalculation(block, text: text, at: request.placement)
        }
    }

    func insertImage(_ image: UIImage) {
        canvas?.insertImage(image)
    }
}
