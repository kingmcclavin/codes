import SwiftUI

/// Style editor for the current selection (color, thickness, fill, opacity,
/// line style, arrow heads). Every change is one undoable action.
struct SelectionInspectorView: View {
    @ObservedObject var editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var width: CGFloat = 2
    @State private var opacity: CGFloat = 1

    var body: some View {
        NavigationStack {
            Form {
                if let sel = editor.selection {
                    if sel.hasInk || sel.hasShapes || sel.hasText {
                        Section("Color") {
                            ColorStrip(editor: editor)
                        }
                    }
                    if sel.hasInk || sel.hasShapes {
                        Section("Line") {
                            VStack(alignment: .leading) {
                                Text("Thickness: \(String(format: "%.1f", width)) pt")
                                Slider(value: $width, in: 0.3...30, onEditingChanged: { editing in
                                    if !editing { applyWidth() }
                                })
                            }
                            Picker("Style", selection: Binding(get: { sel.lineStyle ?? .solid }, set: applyLineStyle)) {
                                ForEach(LineStyle.allCases) { Text($0.displayName).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    if sel.hasFillableShapes {
                        Section("Fill") {
                            HStack {
                                fillButton("None", fill: nil)
                                fillButton("Light", fill: (sel.color ?? .black).withAlpha(0.18))
                                fillButton("Solid", fill: sel.color ?? .black)
                                Spacer()
                                ColorPicker("Custom Fill", selection: Binding(get: { (sel.fill ?? .white).color },
                                                                              set: { applyFill(RGBAColor($0)) }))
                                    .labelsHidden()
                            }
                        }
                    }
                    if sel.hasLines {
                        Section("Arrow Heads") {
                            Toggle("Start", isOn: Binding(get: { sel.arrows?.start ?? false }, set: { v in applyArrows { $0.start = v } }))
                            Toggle("End", isOn: Binding(get: { sel.arrows?.end ?? false }, set: { v in applyArrows { $0.end = v } }))
                        }
                    }
                    Section("Opacity") {
                        VStack(alignment: .leading) {
                            Text("\(Int(opacity * 100))%")
                            Slider(value: $opacity, in: 0.1...1, onEditingChanged: { editing in
                                if !editing { applyOpacity() }
                            })
                        }
                    }
                    Section {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            editor.canvas?.deleteSelection()
                            dismiss()
                        }
                    }
                } else {
                    Text("Nothing selected").foregroundStyle(.secondary)
                }
            }
            .navigationTitle(editor.selection.map { "\($0.count) Selected" } ?? "Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                width = editor.selection?.lineWidth ?? 2
                opacity = editor.selection?.opacity ?? 1
            }
        }
    }

    private func fillButton(_ title: String, fill: RGBAColor?) -> some View {
        Button(title) { applyFill(fill) }
            .buttonStyle(.bordered)
    }

    private func applyWidth() {
        let w = width
        editor.applyToSelection("Line Width") { e in
            switch e {
            case var .stroke(s): s.style.width = w; return .stroke(s)
            case var .shape(s): s.style.lineWidth = w; return .shape(s)
            default: return e
            }
        }
    }

    private func applyOpacity() {
        let o = opacity
        editor.applyToSelection("Opacity") { e in
            switch e {
            case var .stroke(s): s.style.opacity = o; return .stroke(s)
            case var .shape(s): s.style.opacity = o; return .shape(s)
            case var .image(i): i.opacity = o; return .image(i)
            case var .text(t): t.style.color = t.style.color.withAlpha(Double(o)); return .text(t)
            }
        }
    }

    private func applyLineStyle(_ style: LineStyle) {
        editor.applyToSelection("Line Style") { e in
            switch e {
            case var .stroke(s): s.style.lineStyle = style; return .stroke(s)
            case var .shape(s): s.style.lineStyle = style; return .shape(s)
            default: return e
            }
        }
    }

    private func applyFill(_ fill: RGBAColor?) {
        editor.applyToSelection("Fill") { e in
            guard case var .shape(s) = e, s.geometry.isClosed else { return e }
            s.style.fillColor = fill
            return .shape(s)
        }
    }

    private func applyArrows(_ change: @escaping (inout ArrowHeads) -> Void) {
        editor.applyToSelection("Arrow Heads") { e in
            guard case var .shape(s) = e, case .line = s.geometry else { return e }
            change(&s.arrows)
            return .shape(s)
        }
    }
}
