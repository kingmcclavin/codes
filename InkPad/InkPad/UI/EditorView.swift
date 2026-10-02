import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @ObservedObject var editor: EditorModel
    /// Called by the back button; defaults to dismissing the view.
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var calc: CalculatorStore
    @State private var renaming = false
    @State private var renameText = ""
    @AppStorage("floatingCalculatorVisible") private var showCalculator = false
    /// Top-left of the floating calculator, as a fraction of the canvas size.
    @AppStorage("floatingCalculatorX") private var calcX = 0.62
    @AppStorage("floatingCalculatorY") private var calcY = 0.08
    @State private var calcDrag: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(editor: editor, showCalculator: $showCalculator, onClose: close, onRename: {
                renameText = editor.title
                renaming = true
            })
            Divider()
            ToolOptionsBar(editor: editor)
            Divider()
            CanvasRepresentable(editor: editor)
                .ignoresSafeArea(.container, edges: [.bottom, .horizontal])
                .overlay(alignment: .bottomTrailing) {
                    ZoomControl(editor: editor)
                        .padding(14)
                }
                .overlay(alignment: .bottom) {
                    PageIndicator(editor: editor)
                        .padding(.bottom, 14)
                }
                .overlay { floatingCalculator }
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $editor.showPageManager) { PageManagerView(editor: editor) }
        .sheet(isPresented: $editor.showPageSettings) { PageSettingsView(editor: editor) }
        .sheet(isPresented: $editor.showImagePicker) {
            ImagePicker { image in editor.insertImage(image) }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $editor.showSelectionInspector) {
            SelectionInspectorView(editor: editor)
                .presentationDetents([.medium])
        }
        .sheet(item: Binding(get: { editor.shareURL.map(ShareItem.init) }, set: { editor.shareURL = $0?.url })) { item in
            ShareSheet(items: [item.url])
        }
        .alert("Rename Document", isPresented: $renaming) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { if !renameText.isEmpty { editor.title = renameText } }
        }
        .fileImporter(isPresented: $editor.showPDFImporter, allowedContentTypes: [.pdf]) { result in
            if case let .success(url) = result { editor.importPDF(url) }
        }
        .alert("Couldn't Import PDF", isPresented: Binding(get: { editor.importError != nil },
                                                          set: { if !$0 { editor.importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editor.importError ?? "")
        }
        .sheet(item: $editor.calculationRequest) { request in
            CalculationCardEditor(block: request.block, isNew: request.element == nil) { block, text in
                editor.commitCalculation(request, block: block, text: text)
            }
        }
        .onAppear(perform: takePendingCalculation)
        .onChange(of: calc.pendingInsertion) { _, _ in takePendingCalculation() }
        .onDisappear { editor.flush() }
        .persistentSystemOverlays(.hidden)
    }

    // MARK: Floating calculator

    private let calculatorWidth: CGFloat = 300

    @ViewBuilder
    private var floatingCalculator: some View {
        if showCalculator {
            GeometryReader { geo in
                let maxX = max(0, geo.size.width - calculatorWidth)
                let origin = CGPoint(x: (calcX * geo.size.width + calcDrag.width).clamped(0, maxX),
                                     y: (calcY * geo.size.height + calcDrag.height).clamped(0, max(0, geo.size.height - 60)))
                FloatingCalculator(onInsert: insertCalculation, onClose: { withAnimation(.snappy) { showCalculator = false } })
                    .frame(width: calculatorWidth)
                    .gesture(
                        DragGesture(minimumDistance: 4, coordinateSpace: .global)
                            .onChanged { calcDrag = $0.translation }
                            .onEnded { value in
                                let x = (calcX * geo.size.width + value.translation.width).clamped(0, maxX)
                                let y = (calcY * geo.size.height + value.translation.height).clamped(0, max(0, geo.size.height - 60))
                                calcX = geo.size.width > 0 ? x / geo.size.width : 0
                                calcY = geo.size.height > 0 ? y / geo.size.height : 0
                                calcDrag = .zero
                            })
                    .offset(x: origin.x, y: origin.y)
                    .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
            }
        }
    }

    private func insertCalculation(_ expression: String) {
        let block = calc.expressionBlock(expression)
        editor.canvas?.insertCalculation(block, text: calc.renderedText(block))
    }

    /// A calculation sent here from the calculator or a formula.
    private func takePendingCalculation() {
        guard let item = calc.pendingInsertion else { return }
        calc.pendingInsertion = nil
        switch item {
        case let .calculation(block):
            DispatchQueue.main.async { editor.newCalculation(block) }
        case let .image(image):
            insertWhenReady(image, attempts: 10)
        }
    }

    /// The canvas is created a moment after the editor appears.
    private func insertWhenReady(_ image: UIImage, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if editor.canvas != nil {
                editor.insertImage(image)
            } else if attempts > 0 {
                insertWhenReady(image, attempts: attempts - 1)
            }
        }
    }

    private func close() {
        editor.flush()
        if let onClose { onClose() } else { dismiss() }
    }
}

private struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

// MARK: - Top toolbar

struct EditorToolbar: View {
    @ObservedObject var editor: EditorModel
    @Binding var showCalculator: Bool
    let onClose: () -> Void
    let onRename: () -> Void

    private let tools: [ToolKind] = [.pen, .highlighter, .eraser, .shapes, .lasso, .text]

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 6) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Documents")
                Button(action: onRename) {
                    Text(editor.title.isEmpty ? "Untitled" : editor.title)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                ForEach(Array(tools.enumerated()), id: \.element) { index, tool in
                    ToolButton(tool: tool, isSelected: editor.tool == tool, color: color(for: tool)) {
                        editor.selectTool(tool)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
                Divider().frame(height: 24).padding(.horizontal, 4)
                Button { editor.showImagePicker = true } label: {
                    Image(systemName: "photo").frame(width: 40, height: 36)
                }
                .accessibilityLabel("Insert Image")
                Button {
                    withAnimation(.snappy) { showCalculator.toggle() }
                } label: {
                    Image(systemName: "plus.forwardslash.minus")
                        .frame(width: 40, height: 36)
                        .background(RoundedRectangle(cornerRadius: 9).fill(showCalculator ? Color.appAccent.opacity(0.16) : .clear))
                        .foregroundStyle(showCalculator ? Color.appAccent : Color.primary)
                }
                .accessibilityLabel(showCalculator ? "Hide Calculator" : "Show Calculator")
                .keyboardShortcut("k", modifiers: .command)
            }
            .fixedSize()

            HStack(spacing: 2) {
                Button { editor.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 38, height: 36) }
                    .disabled(!editor.canUndo)
                    .keyboardShortcut("z", modifiers: .command)
                    .accessibilityLabel("Undo")
                Button { editor.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 38, height: 36) }
                    .disabled(!editor.canRedo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .accessibilityLabel("Redo")
                Button { editor.showPageManager = true } label: { Image(systemName: "square.stack").frame(width: 38, height: 36) }
                    .accessibilityLabel("Pages")
                Button { editor.showPageSettings = true } label: { Image(systemName: "doc.badge.gearshape").frame(width: 38, height: 36) }
                    .accessibilityLabel("Page Settings")
                EditorMoreMenu(editor: editor)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
        .background(.bar)
    }

    private func color(for tool: ToolKind) -> Color? {
        switch tool {
        case .pen: return editor.settings.pen.color.color
        case .highlighter: return editor.settings.highlighter.color.color
        case .shapes: return editor.settings.shape.strokeColor.color
        default: return nil
        }
    }
}

struct ToolButton: View {
    let tool: ToolKind
    let isSelected: Bool
    let color: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .frame(height: 22)
                Capsule()
                    .fill(color ?? .clear)
                    .frame(width: 14, height: 3)
            }
            .frame(width: 42, height: 40)
            .background(RoundedRectangle(cornerRadius: 9).fill(isSelected ? Color.appAccent.opacity(0.16) : .clear))
            .foregroundStyle(isSelected ? Color.appAccent : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct EditorMoreMenu: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        Menu {
            Button("Add Page", systemImage: "plus.rectangle.portrait") { editor.addPage() }
            Button("Insert Calculation Card…", systemImage: "function") { editor.newCalculation() }
            Button("Import PDF…", systemImage: "doc.richtext") { editor.showPDFImporter = true }
            Button("Export PDF", systemImage: "square.and.arrow.up") { editor.exportPDF() }
            Divider()
            Toggle(isOn: $editor.settings.scribbleToErase) { Label("Scribble to Erase", systemImage: "scribble") }
            Picker(selection: $editor.settings.scribbleMode) {
                ForEach(ScribbleEraseMode.allCases) { Text($0.displayName).tag($0) }
            } label: { Label("Scribble Erases", systemImage: "scribble.variable") }
            Toggle(isOn: $editor.settings.holdToSnapShapes) { Label("Hold to Snap Shapes", systemImage: "hand.point.up.left") }
            Picker(selection: $editor.settings.holdDuration) {
                Text("Short (0.35 s)").tag(0.35)
                Text("Medium (0.5 s)").tag(0.5)
                Text("Long (0.8 s)").tag(0.8)
            } label: { Label("Hold Duration", systemImage: "timer") }
            Toggle(isOn: $editor.settings.fingerDrawing) { Label("Draw with Finger", systemImage: "hand.draw") }
        } label: {
            Image(systemName: "ellipsis.circle").frame(width: 38, height: 36)
        }
        .accessibilityLabel("More")
    }
}

// MARK: - Canvas overlays

struct ZoomControl: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        HStack(spacing: 0) {
            Button { editor.canvas?.zoom(by: 1 / 1.25) } label: {
                Image(systemName: "minus").frame(width: 34, height: 32)
            }
            Menu {
                Button("Fit to Screen Edges", systemImage: "arrow.left.and.right") { editor.canvas?.fitWidth() }
                Button("Fit Whole Page", systemImage: "arrow.down.right.and.arrow.up.left") { editor.canvas?.fitPage() }
                Divider()
                ForEach([50, 100, 150, 200, 400, 800], id: \.self) { p in
                    Button("\(p)%") { editor.canvas?.setZoom(CGFloat(p) / 100) }
                }
            } label: {
                Text("\(editor.zoomPercent)%")
                    .font(.footnote.monospacedDigit().weight(.medium))
                    .frame(minWidth: 52, minHeight: 32)
            }
            Button { editor.canvas?.zoom(by: 1.25) } label: {
                Image(systemName: "plus").frame(width: 34, height: 32)
            }
        }
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator.opacity(0.5)))
    }
}

struct PageIndicator: View {
    @ObservedObject var editor: EditorModel

    private func pageLabel(_ section: String?) -> some View {
        HStack(spacing: 4) {
            if let section {
                Text(section).lineLimit(1).frame(maxWidth: 160)
                Text("·").foregroundStyle(.secondary)
            }
            Text("\(editor.currentPageIndex + 1) / \(editor.pageCount)").monospacedDigit()
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 6)
        .frame(minWidth: 54, minHeight: 30)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button { editor.goToPage(max(0, editor.currentPageIndex - 1)) } label: {
                Image(systemName: "chevron.up").frame(width: 32, height: 30)
            }
            .disabled(editor.currentPageIndex == 0)
            let sections = editor.sections
            if sections.isEmpty {
                Button { editor.showPageManager = true } label: { pageLabel(nil) }
            } else {
                Menu {
                    ForEach(sections) { s in
                        Button("\(s.title) (p. \(s.start + 1))", systemImage: "bookmark") { editor.goToPage(s.start) }
                    }
                    Divider()
                    Button("All Pages…", systemImage: "square.stack") { editor.showPageManager = true }
                } label: {
                    pageLabel(editor.section(containing: editor.currentPageIndex)?.title)
                }
            }
            Button { editor.goToPage(min(editor.pageCount - 1, editor.currentPageIndex + 1)) } label: {
                Image(systemName: "chevron.down").frame(width: 32, height: 30)
            }
            .disabled(editor.currentPageIndex >= editor.pageCount - 1)
            Button { editor.addPage() } label: {
                Image(systemName: "plus").frame(width: 32, height: 30)
            }
            .accessibilityLabel("Add Page")
        }
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator.opacity(0.5)))
    }
}
