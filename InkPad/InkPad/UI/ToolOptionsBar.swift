import SwiftUI

/// Compact, contextual options strip under the toolbar. Keeps colors and
/// sizes one tap away without covering the canvas.
struct ToolOptionsBar: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                switch editor.tool {
                case .pen, .highlighter: InkOptions(editor: editor)
                case .eraser: EraserOptions(editor: editor)
                case .shapes: ShapeOptions(editor: editor)
                case .lasso: LassoOptions(editor: editor)
                case .text: TextOptions(editor: editor)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
        }
        .frame(height: 46)
        .background(.bar)
    }
}

// MARK: - Shared controls

struct ColorStrip: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject private var prefs = AppPreferences.shared
    var palette: [RGBAColor] = RGBAColor.inkPalette

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(palette.enumerated()), id: \.offset) { _, c in swatch(c) }
            if !prefs.recentColors.isEmpty {
                Divider().frame(height: 22)
                ForEach(Array(prefs.recentColors.prefix(5).enumerated()), id: \.offset) { _, c in swatch(c) }
            }
            ColorPicker("Custom Color", selection: Binding(get: { editor.currentColor.color },
                                                           set: { editor.useColor(RGBAColor($0)) }))
                .labelsHidden()
                .frame(width: 28)
        }
    }

    private func swatch(_ c: RGBAColor) -> some View {
        let selected = editor.currentColor.withAlpha(1).isClose(to: c.withAlpha(1))
        return Button { editor.useColor(c) } label: {
            Circle()
                .fill(c.color)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                .frame(width: 24, height: 24)
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

/// Quick width buttons plus a popover slider.
struct WidthPicker: View {
    let quick: [CGFloat]
    let range: ClosedRange<CGFloat>
    @Binding var width: CGFloat
    @State private var showSlider = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(quick.enumerated()), id: \.offset) { i, w in
                Button { width = w } label: {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 5 + CGFloat(i) * 5, height: 5 + CGFloat(i) * 5)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(abs(width - w) < 0.05 ? Color.accentColor.opacity(0.18) : .clear))
                }
                .buttonStyle(.plain)
            }
            Button { showSlider = true } label: {
                Text(String(format: width < 10 ? "%.1f" : "%.0f", width))
                    .font(.footnote.monospacedDigit())
                    .frame(minWidth: 34, minHeight: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSlider) {
                VStack(alignment: .leading) {
                    Text("Thickness: \(String(format: "%.1f", width)) pt").font(.headline)
                    Slider(value: $width, in: range)
                }
                .padding()
                .frame(width: 280)
            }
        }
    }
}

// MARK: - Per-tool bars

struct InkOptions: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var showSettings = false

    private var isHighlighter: Bool { editor.tool == .highlighter }

    var body: some View {
        presetMenu
        Divider().frame(height: 24)
        ColorStrip(editor: editor, palette: isHighlighter ? RGBAColor.highlighterPalette : RGBAColor.inkPalette)
        Divider().frame(height: 24)
        WidthPicker(quick: editor.activeInkStyle.kind.quickWidths, range: editor.activeInkStyle.kind.widthRange,
                    width: $editor.activeInkStyle.width)
        Divider().frame(height: 24)
        Button { showSettings = true } label: {
            Label("Pen Settings", systemImage: "slider.horizontal.3").labelStyle(.iconOnly)
                .frame(width: 34, height: 30)
        }
        .popover(isPresented: $showSettings) {
            PenSettingsView(editor: editor)
        }
        .onChange(of: editor.showToolOptions) { _, _ in showSettings = true }
    }

    private var presetMenu: some View {
        Menu {
            Section("Presets") {
                ForEach(isHighlighter ? PenPreset.builtInHighlighters : PenPreset.builtInPens) { p in
                    Button(p.name, systemImage: p.style.kind.symbol) { apply(p) }
                }
            }
            let custom = prefs.customPresets.filter { ($0.style.kind == .highlighter) == isHighlighter }
            if !custom.isEmpty {
                Section("My Presets") {
                    ForEach(custom) { p in
                        Button(p.name, systemImage: p.style.kind.symbol) { apply(p) }
                    }
                }
                Menu("Delete Preset", systemImage: "trash") {
                    ForEach(custom) { p in
                        Button(p.name, role: .destructive) { prefs.deletePreset(p.id) }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: editor.activeInkStyle.kind.symbol)
                Text(editor.activeInkStyle.kind.displayName).font(.subheadline)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .foregroundStyle(.primary)
        }
    }

    private func apply(_ p: PenPreset) {
        editor.activeInkStyle = p.style
    }
}

struct EraserOptions: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        Picker("Eraser", selection: $editor.settings.eraser.mode) {
            ForEach(EraserMode.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(width: 160)
        Divider().frame(height: 24)
        Image(systemName: "circle").font(.caption2)
        Slider(value: $editor.settings.eraser.size, in: 8...80)
            .frame(width: 160)
        Image(systemName: "circle").font(.title3)
        Divider().frame(height: 24)
        Toggle("Highlighter Only", isOn: $editor.settings.eraser.erasesHighlighterOnly)
            .toggleStyle(.button)
            .font(.subheadline)
        Divider().frame(height: 24)
        Toggle(isOn: $editor.settings.scribbleToErase) {
            Label("Scribble to Erase", systemImage: "scribble")
        }
        .toggleStyle(.button)
        .font(.subheadline)
        Picker("Scribble Erases", selection: $editor.settings.scribbleMode) {
            ForEach(ScribbleEraseMode.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.menu)
        .disabled(!editor.settings.scribbleToErase)
    }
}

struct ShapeOptions: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        ColorStrip(editor: editor)
        Divider().frame(height: 24)
        WidthPicker(quick: [1, 2, 4], range: 0.3...24, width: $editor.settings.shape.lineWidth)
        Divider().frame(height: 24)
        Menu {
            Button("No Fill", systemImage: "circle") { editor.settings.shape.fillColor = nil }
            Button("Light Fill", systemImage: "circle.lefthalf.filled") {
                editor.settings.shape.fillColor = editor.settings.shape.strokeColor.withAlpha(0.18)
            }
            Button("Solid Fill", systemImage: "circle.fill") {
                editor.settings.shape.fillColor = editor.settings.shape.strokeColor
            }
        } label: {
            Label("Fill", systemImage: editor.settings.shape.fillColor == nil ? "circle.dashed" : "circle.fill")
                .font(.subheadline)
        }
        Picker("Line", selection: $editor.settings.shape.lineStyle) {
            ForEach(LineStyle.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.menu)
        Divider().frame(height: 24)
        Text("Draw a rough shape — it snaps when you lift.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

struct LassoOptions: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        if let sel = editor.selection {
            Text("\(sel.count) selected").font(.subheadline.weight(.medium))
            Divider().frame(height: 24)
            Button("Cut", systemImage: "scissors") { editor.canvas?.cutSelection() }
            Button("Copy", systemImage: "doc.on.doc") { editor.canvas?.copySelection() }
            Button("Duplicate", systemImage: "plus.square.on.square") { editor.canvas?.duplicateSelection() }
            Button("Delete", systemImage: "trash", role: .destructive) { editor.canvas?.deleteSelection() }
                .keyboardShortcut(.delete, modifiers: [])
            Divider().frame(height: 24)
            if sel.hasInk || sel.hasShapes || sel.hasText {
                ColorStrip(editor: editor)
            }
            Button("Style", systemImage: "slider.horizontal.3") { editor.showSelectionInspector = true }
        } else {
            Text("Circle items to select them, or tap an item.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if editor.clipboardHasContent {
            Divider().frame(height: 24)
            Button("Paste", systemImage: "doc.on.clipboard") { editor.canvas?.paste() }
                .keyboardShortcut("v", modifiers: .command)
        }
    }
}

struct TextOptions: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        Picker("Font", selection: $editor.settings.text.fontFamily) {
            ForEach(TextStyle.availableFamilies, id: \.self) { f in
                Text(f).tag(f)
            }
        }
        .pickerStyle(.menu)
        Stepper(value: $editor.settings.text.fontSize, in: 6...144, step: 1) {
            Text("\(Int(editor.settings.text.fontSize)) pt").font(.subheadline.monospacedDigit())
        }
        .fixedSize()
        Divider().frame(height: 24)
        ColorStrip(editor: editor)
        Divider().frame(height: 24)
        Toggle(isOn: $editor.settings.text.bold) { Image(systemName: "bold") }
            .toggleStyle(.button)
            .keyboardShortcut("b", modifiers: .command)
        Toggle(isOn: $editor.settings.text.italic) { Image(systemName: "italic") }
            .toggleStyle(.button)
            .keyboardShortcut("i", modifiers: .command)
        Picker("Alignment", selection: $editor.settings.text.alignment) {
            ForEach(TextAlignmentOption.allCases) { a in
                Image(systemName: a.symbol).tag(a)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
        if editor.isEditingText {
            Button("Done") { editor.canvas?.endTextEditing() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }
}
