import SwiftUI

/// Full pen customization popover.
struct PenSettingsView: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var savingPreset = false
    @State private var presetName = ""

    private var isHighlighter: Bool { editor.tool == .highlighter }

    var body: some View {
        let style = $editor.activeInkStyle
        Form {
            Section {
                StrokePreview(style: editor.activeInkStyle)
                    .frame(height: 64)
                    .listRowInsets(EdgeInsets())
            }
            if !isHighlighter {
                Section("Pen Type") {
                    Picker("Type", selection: style.kind) {
                        ForEach(InkKind.allCases.filter { $0 != .highlighter }) { k in
                            Label(k.displayName, systemImage: k.symbol).tag(k)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            Section("Stroke") {
                slider("Thickness", value: style.width, range: editor.activeInkStyle.kind.widthRange, format: "%.1f pt")
                slider("Opacity", value: style.opacity, range: 0.1...1, format: "%.0f%%", scale: 100)
                if !isHighlighter {
                    slider("Pressure Sensitivity", value: style.pressureSensitivity, range: 0...1, format: "%.0f%%", scale: 100)
                    slider("Tilt Shading", value: style.tiltSensitivity, range: 0...1, format: "%.0f%%", scale: 100)
                }
                Picker("Line Style", selection: style.lineStyle) {
                    ForEach(LineStyle.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Button("Save as Preset…", systemImage: "star") {
                    presetName = editor.activeInkStyle.kind.displayName
                    savingPreset = true
                }
            }
        }
        .frame(width: 360, height: isHighlighter ? 420 : 560)
        .alert("Save Preset", isPresented: $savingPreset) {
            TextField("Name", text: $presetName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                prefs.savePreset(name: presetName.isEmpty ? "Preset" : presetName, style: editor.activeInkStyle)
            }
        }
    }

    private func slider(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, format: String, scale: CGFloat = 1) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue * scale))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }
}

/// Renders a sample stroke with the real stroke engine.
struct StrokePreview: View {
    let style: StrokeStyle

    var body: some View {
        Canvas { ctx, size in
            let n = 60
            var points: [InkPoint] = []
            for i in 0...n {
                let t = CGFloat(i) / CGFloat(n)
                let x = 24 + t * (size.width - 48)
                let y = size.height / 2 + sin(t * .pi * 2) * size.height * 0.22
                // Simulated pressure ramp so pressure sensitivity is visible.
                let force = 0.08 + 0.5 * sin(t * .pi)
                points.append(InkPoint(location: CGPoint(x: x, y: y), force: force, altitude: .pi / 2 - t * 1.1))
            }
            let path = Path(StrokePathBuilder.path(points: points, style: style))
            ctx.fill(path, with: .color(style.color.withAlpha(style.color.a * Double(style.opacity)).color))
        }
        .background(Color.white)
    }
}
