import Charts
import SwiftUI
import UIKit

// MARK: - Palette

/// Validated categorical series colors (fixed order, light/dark variants).
enum ChartPalette {
    private static let light: [UInt32] = [0x2A78D6, 0xEB6834, 0x1BAF7A, 0xEDA100, 0xE87BA4, 0x008300, 0x4A3AA7, 0xE34948]
    private static let dark: [UInt32] = [0x3987E5, 0xD95926, 0x199E70, 0xC98500, 0xD55181, 0x008300, 0x9085E9, 0xE66767]

    static let count = light.count

    /// Series color for slot `i` (slots never repaint when others are hidden).
    static func color(_ i: Int) -> Color {
        let l = light[i % count], d = dark[i % count]
        return Color(uiColor: UIColor { traits in
            uiColor(traits.userInterfaceStyle == .dark ? d : l)
        })
    }

    /// Light variant only (for images placed on paper).
    static func paperColor(_ i: Int) -> Color { Color(uiColor: uiColor(light[i % count])) }

    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Renders a view to an image for placing on a note page (always light).
@MainActor
func renderForNote<V: View>(_ view: V, size: CGSize) -> UIImage? {
    let content = view
        .frame(width: size.width, height: size.height)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    return renderer.uiImage
}

// MARK: - Function graph model

struct PlotFunction: Identifiable, Hashable {
    var id: Int          // palette slot
    var expression: String
}

struct GraphSettings: Equatable {
    var functions: [PlotFunction]
    var xMin: Double
    var xMax: Double
    /// nil = automatic
    var yRange: ClosedRange<Double>?
}

/// Pre-computed curves for a graph.
struct GraphData {
    struct Curve: Identifiable {
        var id: Int
        var label: String
        var segments: [[FunctionSampler.Point]]
        var error: String?
    }
    var curves: [Curve]
    var yDomain: ClosedRange<Double>

    init(settings: GraphSettings, engine: CalculatorEngine) {
        curves = settings.functions.map { f in
            let text = f.expression.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return Curve(id: f.id, label: "", segments: [], error: nil) }
            // Accept "y = …" or "f(x) = …".
            var body = text
            if let eq = text.lastIndex(of: "=") { body = String(text[text.index(after: eq)...]) }
            do {
                let expr = try engine.compile(body, names: ["x"])
                let segs = FunctionSampler.sample(expr, engine: engine, xMin: settings.xMin, xMax: settings.xMax)
                return Curve(id: f.id, label: "y = " + MathText.pretty(body.trimmingCharacters(in: .whitespaces)),
                             segments: segs, error: segs.isEmpty ? "Undefined on this range" : nil)
            } catch {
                return Curve(id: f.id, label: text, segments: [], error: error.localizedDescription)
            }
        }
        yDomain = settings.yRange ?? FunctionSampler.autoRange(curves.flatMap(\.segments))
    }
}

/// The chart itself (shared by the screen and note images).
struct FunctionChart: View {
    let data: GraphData
    let xDomain: ClosedRange<Double>
    var forPaper = false
    var trace: Double? = nil

    private func color(_ slot: Int) -> Color { forPaper ? ChartPalette.paperColor(slot) : ChartPalette.color(slot) }

    var body: some View {
        let visible = data.curves.filter { !$0.segments.isEmpty }
        Chart {
            if xDomain.contains(0) { RuleMark(x: .value("x", 0)).foregroundStyle(.secondary.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1)) }
            if data.yDomain.contains(0) { RuleMark(y: .value("y", 0)).foregroundStyle(.secondary.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1)) }
            ForEach(visible) { curve in
                ForEach(Array(curve.segments.enumerated()), id: \.offset) { index, segment in
                    ForEach(segment, id: \.self) { p in
                        LineMark(x: .value("x", p.x), y: .value("y", clamp(p.y)),
                                 series: .value("curve", "\(curve.id)-\(index)"))
                            .foregroundStyle(color(curve.id))
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.linear)
                    }
                }
            }
            if let trace {
                RuleMark(x: .value("trace", trace)).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                ForEach(visible) { curve in
                    if let y = value(of: curve, at: trace), data.yDomain.contains(y) {
                        PointMark(x: .value("x", trace), y: .value("y", y))
                            .foregroundStyle(color(curve.id))
                            .symbolSize(70)
                    }
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: data.yDomain)
        .chartLegend(.hidden)
        .chartPlotStyle { $0.clipped() }
    }

    /// Keeps asymptotes from stretching far outside the plot (they're clipped).
    private func clamp(_ y: Double) -> Double {
        let span = data.yDomain.upperBound - data.yDomain.lowerBound
        return min(max(y, data.yDomain.lowerBound - span), data.yDomain.upperBound + span)
    }

    func value(of curve: GraphData.Curve, at x: Double) -> Double? {
        for seg in curve.segments {
            guard let first = seg.first, let last = seg.last, first.x <= x, x <= last.x else { continue }
            if let i = seg.firstIndex(where: { $0.x >= x }) {
                if i == 0 { return seg[0].y }
                let a = seg[i - 1], b = seg[i]
                let t = (x - a.x) / max(b.x - a.x, 1e-12)
                return a.y + t * (b.y - a.y)
            }
        }
        return nil
    }
}

/// Legend row with a swatch per function (identity is never color alone).
struct GraphLegend: View {
    let curves: [GraphData.Curve]
    var forPaper = false

    var body: some View {
        HStack(spacing: 16) {
            ForEach(curves.filter { !$0.segments.isEmpty }) { c in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(forPaper ? ChartPalette.paperColor(c.id) : ChartPalette.color(c.id))
                        .frame(width: 16, height: 3)
                    Text(c.label).font(.caption.monospaced()).foregroundStyle(.primary)
                }
            }
        }
    }
}

// MARK: - Function grapher screen

struct FunctionGraphView: View {
    @EnvironmentObject private var calc: CalculatorStore
    @AppStorage("graphFunctions") private var storedFunctions = "sin(x)\nx^2/10"
    @AppStorage("graphXMin") private var xMin = -10.0
    @AppStorage("graphXMax") private var xMax = 10.0
    @AppStorage("graphAngle") private var graphAngle = AngleMode.radians
    @State private var autoY = true
    @State private var yMinText = "-10"
    @State private var yMaxText = "10"
    @State private var trace: Double?
    @State private var xMinText = ""
    @State private var xMaxText = ""

    private var functions: [PlotFunction] {
        let parts = storedFunctions.components(separatedBy: "\n")
        return (0..<ChartPalette.count).map { PlotFunction(id: $0, expression: $0 < parts.count ? parts[$0] : "") }
    }

    private func setFunction(_ i: Int, _ text: String) {
        var parts = storedFunctions.components(separatedBy: "\n")
        while parts.count <= i { parts.append("") }
        parts[i] = text.replacingOccurrences(of: "\n", with: " ")
        while parts.last == "" { parts.removeLast() }
        storedFunctions = parts.joined(separator: "\n")
    }

    private var visibleCount: Int {
        let parts = storedFunctions.components(separatedBy: "\n")
        return min(ChartPalette.count, max(1, parts.count + (parts.last?.isEmpty == false ? 1 : 0)))
    }

    private var settings: GraphSettings {
        var yRange: ClosedRange<Double>?
        if !autoY, let lo = try? calc.engine.evaluate(expression: yMinText, values: [:]),
           let hi = try? calc.engine.evaluate(expression: yMaxText, values: [:]), hi > lo {
            yRange = lo...hi
        }
        return GraphSettings(functions: Array(functions.prefix(visibleCount)), xMin: xMin, xMax: max(xMax, xMin + 1e-9), yRange: yRange)
    }

    var body: some View {
        let data = GraphData(settings: settings, engine: graphEngine)
        GeometryReader { geo in
            let wide = geo.size.width > 760
            let layout = wide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                VStack(alignment: .leading, spacing: 8) {
                    GraphLegend(curves: data.curves)
                    chart(data)
                    traceReadout(data)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                controls(data)
                    .frame(width: wide ? 340 : nil, height: wide ? nil : 300)
            }
        }
        .navigationTitle("Function Grapher")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                InsertIntoNotebookMenu(item: { noteImage(data) }) {
                    Label("Insert into Notebook", systemImage: "note.text.badge.plus")
                }
            }
        }
        .onAppear {
            xMinText = NumberFormatting.plain(xMin)
            xMaxText = NumberFormatting.plain(xMax)
        }
    }

    /// The grapher has its own angle unit (radians by default, as on graphing calculators).
    private var graphEngine: CalculatorEngine {
        CalculatorEngine(angleMode: graphAngle, formulas: calc.allFormulas, variables: calc.variables)
    }

    private func chart(_ data: GraphData) -> some View {
        FunctionChart(data: data, xDomain: xMin...max(xMax, xMin + 1e-9), trace: trace)
            .chartOverlay { proxy in
                GeometryReader { g in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let frame = proxy.plotFrame.map({ g[$0] }) else { return }
                                let x = value.location.x - frame.origin.x
                                if let v: Double = proxy.value(atX: x) { trace = min(max(v, xMin), xMax) }
                            })
                }
            }
    }

    @ViewBuilder
    private func traceReadout(_ data: GraphData) -> some View {
        if let trace {
            let chart = FunctionChart(data: data, xDomain: xMin...xMax)
            HStack(spacing: 14) {
                Text("x = \(NumberFormatting.format(trace, digits: 6))").font(.callout.monospaced())
                ForEach(data.curves.filter { !$0.segments.isEmpty }) { c in
                    HStack(spacing: 4) {
                        Circle().fill(ChartPalette.color(c.id)).frame(width: 8, height: 8)
                        Text(chart.value(of: c, at: trace).map { "y = " + NumberFormatting.format($0, digits: 6) } ?? "—")
                            .font(.callout.monospaced())
                    }
                }
                Spacer()
                Button("Clear", systemImage: "xmark.circle") { self.trace = nil }.labelStyle(.iconOnly)
            }
        } else {
            Text("Drag across the graph to trace values.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func controls(_ data: GraphData) -> some View {
        Form {
            Section("Functions of x") {
                ForEach(0..<visibleCount, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            RoundedRectangle(cornerRadius: 1).fill(ChartPalette.color(i)).frame(width: 14, height: 3)
                            TextField("e.g. sin(x), x^2 − 3", text: Binding(get: { functions[i].expression }, set: { setFunction(i, $0) }))
                                .font(.body.monospaced())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        if let e = data.curves.first(where: { $0.id == i })?.error {
                            Text(e).font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            }
            Section {
                rangeField("x min", text: $xMinText) { xMin = $0 }
                rangeField("x max", text: $xMaxText) { xMax = $0 }
                Picker("Angles", selection: $graphAngle) {
                    ForEach(AngleMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Automatic y range", isOn: $autoY)
                if !autoY {
                    rangeField("y min", text: $yMinText) { _ in }
                    rangeField("y max", text: $yMaxText) { _ in }
                }
                HStack {
                    Button("±10") { setX(-10, 10) }
                    Button("0 – 2π") { setX(0, 2 * .pi) }
                    Button("±2π") { setX(-2 * .pi, 2 * .pi) }
                    Button("0 – 100") { setX(0, 100) }
                }
                .buttonStyle(.bordered)
            } header: {
                Text("Window")
            } footer: {
                Text("Use x as the variable. Calculator variables, constants (π, e, g0) and functions all work.")
            }
        }
    }

    private func setX(_ lo: Double, _ hi: Double) {
        xMin = lo; xMax = hi
        xMinText = NumberFormatting.plain(lo); xMaxText = NumberFormatting.plain(hi)
        trace = nil
    }

    private func rangeField(_ label: String, text: Binding<String>, apply: @escaping (Double) -> Void) -> some View {
        LabeledContent(label) {
            TextField(label, text: text)
                .multilineTextAlignment(.trailing)
                .font(.body.monospaced())
                .keyboardType(.numbersAndPunctuation)
                .onSubmit {
                    if let v = try? calc.engine.evaluate(expression: text.wrappedValue, values: [:]), v.isFinite { apply(v) }
                }
                .onChange(of: text.wrappedValue) { _, t in
                    if let v = try? calc.engine.evaluate(expression: t, values: [:]), v.isFinite { apply(v) }
                }
        }
    }

    private func noteImage(_ data: GraphData) -> NoteInsertion? {
        let view = VStack(alignment: .leading, spacing: 10) {
            GraphLegend(curves: data.curves, forPaper: true)
            FunctionChart(data: data, xDomain: xMin...max(xMax, xMin + 1e-9), forPaper: true)
        }
        .padding(18)
        return renderForNote(view, size: CGSize(width: 640, height: 420)).map(NoteInsertion.image)
    }
}
