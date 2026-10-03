import Charts
import SwiftUI
import UIKit

// MARK: - Shared helpers

/// A numeric text field that accepts expressions (`2π`, `1/3`, `g0`).
private struct ExpressionField: View {
    let label: String
    @Binding var text: String
    var unit: String = ""
    @EnvironmentObject private var calc: CalculatorStore

    var value: Double? { try? calc.engine.evaluate(expression: text, values: [:]) }

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                TextField("0", text: $text)
                    .multilineTextAlignment(.trailing)
                    .font(.body.monospaced())
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(!text.isEmpty && value == nil ? Color.red : Color.primary)
                if !unit.isEmpty { Text(unit).foregroundStyle(.secondary) }
            }
        } label: {
            Text(label)
        }
    }
}

@MainActor
private func evaluate(_ text: String, _ calc: CalculatorStore) -> Double? {
    let t = text.trimmingCharacters(in: .whitespaces)
    guard !t.isEmpty, let v = try? calc.engine.evaluate(expression: t, values: [:]), v.isFinite else { return nil }
    return v
}

private struct ResultRow: View {
    let label: String
    let value: String
    var body: some View {
        LabeledContent(label) {
            Text(value).font(.body.monospaced()).textSelection(.enabled)
        }
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = value }
        }
    }
}

private func fmt(_ v: Double, _ digits: Int = 8) -> String { NumberFormatting.format(v, digits: digits) }

// MARK: - Equation solver

struct EquationSolverView: View {
    @EnvironmentObject private var calc: CalculatorStore
    @AppStorage("solverEquation") private var equation = "x^3 - 2x = 5"
    @AppStorage("solverLow") private var lowText = "-100"
    @AppStorage("solverHigh") private var highText = "100"

    private var result: Solver.EquationResult? {
        guard let lo = evaluate(lowText, calc), let hi = evaluate(highText, calc), hi > lo,
              !equation.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Solver.solve(equation, engine: calc.engine, lo: lo, hi: hi)
    }

    var body: some View {
        Form {
            Section {
                TextField("Equation, e.g. x^2 = 2 or cos(x) = x", text: $equation)
                    .font(.title3.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Equation")
            } footer: {
                Text("One unknown (x by default). Without “=”, the expression is set equal to 0. Trig uses the calculator's angle unit.")
            }
            Section("Search Between") {
                ExpressionField(label: "From", text: $lowText)
                ExpressionField(label: "To", text: $highText)
            }
            Section("Solutions") {
                if let r = result {
                    if let e = r.error, r.roots.isEmpty {
                        Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                    ForEach(Array(r.roots.enumerated()), id: \.offset) { i, x in
                        ResultRow(label: r.roots.count > 1 ? "\(r.variable)\(subscriptDigits(i + 1))" : r.variable, value: fmt(x, 12))
                    }
                } else {
                    Text("Enter an equation and a valid range.").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Equation Solver")
    }
}

private func subscriptDigits(_ n: Int) -> String {
    let map: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉"]
    return String(String(n).compactMap { map[$0] })
}

// MARK: - Solve a formula for an input

/// Runs a formula backwards: pick the unknown input and the result you want.
struct FormulaSolveView: View {
    let formula: Formula
    var initialInputs: [String: String] = [:]
    @EnvironmentObject private var calc: CalculatorStore
    @Environment(\.dismiss) private var dismiss
    @State private var unknown = ""
    @State private var output = ""
    @State private var target = ""
    @State private var inputs: [String: String] = [:]
    @State private var loaded = false

    private var engine: CalculatorEngine { calc.engine }
    private var inputNames: [String] { engine.inputs(of: formula) }

    private var roots: [Double]? {
        guard !unknown.isEmpty, !output.isEmpty, let t = evaluate(target, calc) else { return nil }
        var knowns: [String: Double] = [:]
        for n in inputNames where n != unknown {
            if let v = evaluate(inputs[n] ?? "", calc) { knowns[n] = v }
        }
        return Solver.solve(formula, engine: engine, unknown: unknown, knowns: knowns, output: output, target: t)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(formula.lines, id: \.self) { Text(MathText.pretty($0)).font(.system(.title3, design: .serif)) }
                }
                Section("Solve For") {
                    Picker("Unknown", selection: $unknown) {
                        ForEach(inputNames, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Known result", selection: $output) {
                        ForEach(formula.outputNames.isEmpty ? ["Result"] : formula.outputNames, id: \.self) { Text($0).tag($0) }
                    }
                    ExpressionField(label: "\(output) =", text: $target, unit: formula.unit(of: output))
                }
                Section("Other Inputs") {
                    ForEach(inputNames.filter { $0 != unknown }, id: \.self) { n in
                        ExpressionField(label: n, text: Binding(get: { inputs[n] ?? "" }, set: { inputs[n] = $0 }),
                                        unit: unit(of: n))
                    }
                }
                Section("Solution") {
                    if let roots {
                        if roots.isEmpty {
                            Label("No solution found. Check the values (the search covers ±10⁻⁶ … ±10⁹).",
                                  systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        }
                        ForEach(Array(roots.enumerated()), id: \.offset) { _, x in
                            ResultRow(label: unknown, value: fmt(x, 10) + (unit(of: unknown).isEmpty ? "" : " \(unit(of: unknown))"))
                        }
                    } else {
                        Text("Enter the known result.").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Solve \(formula.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                inputs = initialInputs
                unknown = inputNames.last ?? ""
                output = formula.outputNames.first ?? "Result"
            }
        }
    }

    private func unit(of name: String) -> String {
        if let v = formula.variable(name) { return v.unit }
        return calc.allFormulas.first { $0.variable(name) != nil }?.unit(of: name) ?? ""
    }
}

// MARK: - Matrices

struct MatrixCalculatorView: View {
    @EnvironmentObject private var calc: CalculatorStore
    @State private var a = MatrixInput(rows: 3, cols: 3, identity: true)
    @State private var b = MatrixInput(rows: 3, cols: 1)
    @State private var operation: Operation = .determinant

    enum Operation: String, CaseIterable, Identifiable {
        case add = "A + B", subtract = "A − B", multiply = "A · B", transpose = "Aᵀ"
        case determinant = "det A", inverse = "A⁻¹", rank = "rank A", solve = "Solve A·x = B"
        var id: String { rawValue }
        var usesB: Bool { [.add, .subtract, .multiply, .solve].contains(self) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Operation", selection: $operation) {
                    ForEach(Operation.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                MatrixEditor(title: "A", input: $a)
                if operation.usesB { MatrixEditor(title: "B", input: $b) }
                Divider()
                resultView
            }
            .padding(20)
        }
        .navigationTitle("Matrices")
    }

    @ViewBuilder
    private var resultView: some View {
        let result = compute()
        Text("Result").font(.headline)
        switch result {
        case let .success(.matrix(m)):
            MatrixGrid(matrix: m)
        case let .success(.scalar(v)):
            Text(fmt(v, 12)).font(.title2.monospaced()).textSelection(.enabled)
        case let .failure(e):
            Label(e.localizedDescription, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
    }

    private enum Output { case matrix(Matrix), scalar(Double) }

    private func compute() -> Result<Output, Error> {
        Result {
            let ma = try a.matrix(calc), mb = try b.matrix(calc)
            switch operation {
            case .add: return .matrix(try ma + mb)
            case .subtract: return .matrix(try ma - mb)
            case .multiply: return .matrix(try ma * mb)
            case .transpose: return .matrix(ma.transposed)
            case .determinant: return .scalar(try ma.determinant())
            case .inverse: return .matrix(try ma.inverse())
            case .rank: return .scalar(Double(ma.rank))
            case .solve: return .matrix(try ma.solve(mb))
            }
        }
    }
}

struct MatrixInput: Equatable {
    var rows: Int
    var cols: Int
    var cells: [[String]]

    init(rows: Int, cols: Int, identity: Bool = false) {
        self.rows = rows
        self.cols = cols
        cells = (0..<6).map { r in (0..<6).map { c in identity && r == c ? "1" : "0" } }
    }

    struct CellError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    @MainActor
    func matrix(_ calc: CalculatorStore) throws -> Matrix {
        var m = Matrix(rows: rows, cols: cols)
        for r in 0..<rows { for c in 0..<cols {
            let t = cells[r][c].trimmingCharacters(in: .whitespaces)
            guard let v = t.isEmpty ? 0 : evaluate(t, calc) else { throw CellError(message: "Can't read row \(r + 1), column \(c + 1)") }
            m[r, c] = v
        } }
        return m
    }
}

private struct MatrixEditor: View {
    let title: String
    @Binding var input: MatrixInput

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.title3.weight(.semibold))
                Spacer()
                Stepper("\(input.rows) rows", value: $input.rows, in: 1...6).fixedSize()
                Stepper("\(input.cols) cols", value: $input.cols, in: 1...6).fixedSize()
            }
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(0..<input.rows, id: \.self) { r in
                    GridRow {
                        ForEach(0..<input.cols, id: \.self) { c in
                            TextField("0", text: $input.cells[r][c])
                                .multilineTextAlignment(.center)
                                .font(.body.monospaced())
                                .keyboardType(.numbersAndPunctuation)
                                .frame(width: 72, height: 36)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color(uiColor: .tertiarySystemFill)))
                        }
                    }
                }
            }
        }
    }
}

private struct MatrixGrid: View {
    let matrix: Matrix
    var body: some View {
        Grid(horizontalSpacing: 14, verticalSpacing: 6) {
            ForEach(0..<matrix.rows, id: \.self) { r in
                GridRow {
                    ForEach(0..<matrix.cols, id: \.self) { c in
                        Text(fmt(Solver.clean(matrix[r, c]), 6)).font(.body.monospaced())
                    }
                }
            }
        }
        .padding(10)
        .overlay(alignment: .leading) { BracketShape().stroke(.secondary, lineWidth: 1.5).frame(width: 8) }
        .overlay(alignment: .trailing) { BracketShape().stroke(.secondary, lineWidth: 1.5).frame(width: 8).scaleEffect(x: -1) }
        .textSelection(.enabled)
    }
}

private struct BracketShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}

// MARK: - Vectors

struct VectorCalculatorView: View {
    @EnvironmentObject private var calc: CalculatorStore
    @State private var a = ["3", "4", "0"]
    @State private var b = ["1", "0", "2"]

    private func vector(_ t: [String]) -> Vector3? {
        let v = t.map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : evaluate($0, calc) }
        guard let x = v[0], let y = v[1], let z = v[2] else { return nil }
        return Vector3(x: x, y: y, z: z)
    }

    var body: some View {
        Form {
            vectorSection("A", $a)
            vectorSection("B", $b)
            Section("Results") {
                if let va = vector(a), let vb = vector(b) {
                    ResultRow(label: "|A|", value: fmt(va.magnitude))
                    ResultRow(label: "|B|", value: fmt(vb.magnitude))
                    ResultRow(label: "A + B", value: (va + vb).text)
                    ResultRow(label: "A − B", value: (va - vb).text)
                    ResultRow(label: "A · B", value: fmt(va.dot(vb)))
                    ResultRow(label: "A × B", value: va.cross(vb).text)
                    if let angle = va.angle(to: vb) {
                        ResultRow(label: "Angle", value: "\(fmt(angle * 180 / .pi)) °  (\(fmt(angle)) rad)")
                    }
                    if let u = va.unit { ResultRow(label: "Unit A", value: u.text) }
                    if let p = va.projection(onto: vb) { ResultRow(label: "Projection of A on B", value: p.text) }
                    ResultRow(label: "Area of parallelogram", value: fmt(va.cross(vb).magnitude))
                } else {
                    Text("Enter numbers for every component.").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Vectors")
    }

    private func vectorSection(_ name: String, _ v: Binding<[String]>) -> some View {
        Section("Vector \(name)") {
            HStack {
                ForEach(0..<3, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(["x", "y", "z"][i]).font(.caption).foregroundStyle(.secondary)
                        TextField("0", text: v[i])
                            .font(.body.monospaced())
                            .keyboardType(.numbersAndPunctuation)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }
}

// MARK: - Number bases

struct NumberBaseView: View {
    @State private var text = "255"
    @State private var base: NumberBase = .decimal
    @State private var bits = 0   // 0 = automatic

    private var value: Int64? { NumberBase.parse(text, base: base) }

    var body: some View {
        Form {
            Section {
                TextField("Number", text: $text)
                    .font(.title3.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Input base", selection: $base) {
                    ForEach(NumberBase.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Bit width", selection: $bits) {
                    Text("Auto").tag(0)
                    ForEach([8, 16, 32, 64], id: \.self) { Text("\($0)-bit").tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Prefixes 0x, 0b and 0o also work. Negative numbers are shown in two's complement.")
            }
            Section("Value") {
                if let v = value {
                    let width = bits == 0 ? NumberBase.bitsNeeded(v) : bits
                    ForEach(NumberBase.allCases) { b in
                        ResultRow(label: b.name, value: b.format(v, bits: width))
                    }
                    if v >= 0, v <= 0x10FFFF, let scalar = Unicode.Scalar(UInt32(v)), v >= 32 {
                        ResultRow(label: "Character", value: String(Character(scalar)))
                    }
                    ResultRow(label: "Bits set", value: "\(UInt64(bitPattern: v).nonzeroBitCount)")
                } else {
                    Text(text.isEmpty ? "Enter a number." : "Not a valid \(base.name.lowercased()) number.")
                        .foregroundStyle(text.isEmpty ? Color.secondary : Color.red)
                }
            }
        }
        .navigationTitle("Number Bases")
    }
}

// MARK: - Section properties

struct SectionPropertiesView: View {
    @EnvironmentObject private var calc: CalculatorStore
    @State private var shape: SectionShape = .iBeam
    @State private var dims: [String: String] = ["b": "100", "h": "200", "tf": "10", "tw": "6", "t": "5", "d": "50", "D": "60"]
    @AppStorage("sectionUnit") private var unit = "mm"

    private var properties: Result<SectionProperties, Error> {
        var values: [String: Double] = [:]
        for d in shape.dimensions { values[d.key] = evaluate(dims[d.key] ?? "", calc) }
        return Result { try SectionProperties.compute(shape, values) }
    }

    var body: some View {
        Form {
            Section {
                Picker("Shape", selection: $shape) {
                    ForEach(SectionShape.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Unit", selection: $unit) {
                    ForEach(["mm", "cm", "m", "in"], id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                ForEach(shape.dimensions, id: \.key) { d in
                    ExpressionField(label: d.label, text: Binding(get: { dims[d.key] ?? "" }, set: { dims[d.key] = $0 }), unit: unit)
                }
            }
            if case let .success(p) = properties {
                Section {
                    SectionSketch(shape: shape, dims: dims.compactMapValues { Double($0) }, properties: p)
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                }
                Section("Properties") {
                    ResultRow(label: "Area A", value: "\(fmt(p.area, 6)) \(unit)²")
                    ResultRow(label: "Centroid from bottom ȳ", value: "\(fmt(p.centroidY, 6)) \(unit)")
                    ResultRow(label: "Iₓ (strong axis)", value: "\(fmt(p.ix, 6)) \(unit)⁴")
                    ResultRow(label: "I_y (weak axis)", value: "\(fmt(p.iy, 6)) \(unit)⁴")
                    ResultRow(label: "Sₓ (elastic modulus)", value: "\(fmt(p.sx, 6)) \(unit)³")
                    ResultRow(label: "S_y", value: "\(fmt(p.sy, 6)) \(unit)³")
                    ResultRow(label: "rₓ (radius of gyration)", value: "\(fmt(p.rx, 6)) \(unit)")
                    ResultRow(label: "r_y", value: "\(fmt(p.ry, 6)) \(unit)")
                    ResultRow(label: "J (polar, Iₓ + I_y)", value: "\(fmt(p.polar, 6)) \(unit)⁴")
                }
            } else if case let .failure(e) = properties {
                Section { Label(e.localizedDescription, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
        }
        .navigationTitle("Section Properties")
    }
}

/// Scaled outline of a section with its centroid.
private struct SectionSketch: View {
    let shape: SectionShape
    let dims: [String: Double]
    let properties: SectionProperties

    var body: some View {
        Canvas { ctx, size in
            let w = properties.width, h = properties.height
            guard w > 0, h > 0 else { return }
            let s = min((size.width - 20) / w, (size.height - 20) / h)
            let origin = CGPoint(x: (size.width - w * s) / 2, y: (size.height + h * s) / 2)   // bottom-left
            func rect(_ x: Double, _ y: Double, _ rw: Double, _ rh: Double) -> CGRect {
                CGRect(x: origin.x + (w / 2 + x - rw / 2) * s, y: origin.y - (y + rh) * s, width: rw * s, height: rh * s)
            }
            var path = Path()
            let d = { (k: String) in dims[k] ?? 0 }
            switch shape {
            case .rectangle: path.addRect(rect(0, 0, w, h))
            case .hollowRectangle:
                path.addRect(rect(0, 0, w, h))
                path.addRect(rect(0, d("t"), w - 2 * d("t"), h - 2 * d("t")))
            case .circle: path.addEllipse(in: rect(0, 0, w, h))
            case .tube:
                path.addEllipse(in: rect(0, 0, w, h))
                path.addEllipse(in: rect(0, d("t"), w - 2 * d("t"), h - 2 * d("t")))
            case .iBeam:
                path.addRect(rect(0, 0, w, d("tf")))
                path.addRect(rect(0, d("tf"), d("tw"), h - 2 * d("tf")))
                path.addRect(rect(0, h - d("tf"), w, d("tf")))
            case .tee:
                path.addRect(rect(0, 0, d("tw"), h - d("tf")))
                path.addRect(rect(0, h - d("tf"), w, d("tf")))
            }
            ctx.fill(path, with: .color(ChartPalette.color(0).opacity(0.25)), style: FillStyle(eoFill: true))
            ctx.stroke(path, with: .color(ChartPalette.color(0)), lineWidth: 1.5)
            // Centroidal axis
            let cy = origin.y - properties.centroidY * s
            var axis = Path()
            axis.move(to: CGPoint(x: origin.x - 8, y: cy))
            axis.addLine(to: CGPoint(x: origin.x + w * s + 8, y: cy))
            ctx.stroke(axis, with: .color(.secondary), style: SwiftUI.StrokeStyle(lineWidth: 1, dash: [5, 4]))
            ctx.fill(Path(ellipseIn: CGRect(x: size.width / 2 - 4, y: cy - 4, width: 8, height: 8)), with: .color(.primary))
        }
    }
}

// MARK: - Beam calculator

struct BeamCalculatorView: View {
    @EnvironmentObject private var calc: CalculatorStore
    @State private var support: Beam.Support = .simplySupported
    @State private var lengthText = "6"
    @State private var eText = "200"
    @State private var iText = "8.36e7"
    @State private var loads: [LoadInput] = [LoadInput(kind: .point, magnitude: "10", start: "3", end: "")]

    struct LoadInput: Identifiable, Equatable {
        enum Kind: String, CaseIterable, Identifiable {
            case point = "Point Load", distributed = "Distributed", moment = "Moment"
            var id: String { rawValue }
        }
        var id = UUID()
        var kind: Kind
        var magnitude: String
        var start: String
        var end: String
    }

    /// SI beam (N, m, Pa·m⁴) from the form, which uses kN, m, GPa and mm⁴.
    private var beam: Result<Beam, Error> {
        Result {
            guard let l = evaluate(lengthText, calc), l > 0 else { throw Beam.BeamError.invalid("Enter the span") }
            var b = Beam(support: support, length: l, loads: [])
            for input in loads {
                guard let m = evaluate(input.magnitude, calc), let a = evaluate(input.start, calc) else {
                    throw Beam.BeamError.invalid("Complete every load")
                }
                switch input.kind {
                case .point: b.loads.append(.point(p: m * 1000, a: a))
                case .moment: b.loads.append(.moment(m: m * 1000, a: a))
                case .distributed:
                    guard let e = evaluate(input.end, calc) else { throw Beam.BeamError.invalid("Enter where the distributed load ends") }
                    b.loads.append(.distributed(w: m * 1000, a: a, b: e))
                }
            }
            if let e = evaluate(eText, calc), let i = evaluate(iText, calc), e > 0, i > 0 {
                b.ei = e * 1e9 * i * 1e-12
            }
            return b
        }
    }

    var body: some View {
        let analysis = beam.flatMap { b in Result { (b, try b.analyze()) } }
        GeometryReader { geo in
            let wide = geo.size.width > 820
            let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                form
                    .frame(width: wide ? 380 : nil, height: wide ? nil : 360)
                Divider()
                ScrollView {
                    switch analysis {
                    case let .success((b, r)):
                        BeamResultsView(beam: b, results: r)
                            .padding(18)
                    case let .failure(e):
                        Label(e.localizedDescription, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .padding(30)
                    }
                }
            }
        }
        .navigationTitle("Beam Calculator")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                InsertIntoNotebookMenu(item: {
                    guard case let .success((b, r)) = analysis else { return nil }
                    let view = BeamResultsView(beam: b, results: r, forPaper: true).padding(18)
                    return renderForNote(view, size: CGSize(width: 620, height: 900)).map(NoteInsertion.image)
                }) {
                    Label("Insert into Notebook", systemImage: "note.text.badge.plus")
                }
            }
        }
    }

    private var form: some View {
        Form {
            Section("Beam") {
                Picker("Support", selection: $support) {
                    ForEach(Beam.Support.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                ExpressionField(label: "Span L", text: $lengthText, unit: "m")
                ExpressionField(label: "Elastic modulus E", text: $eText, unit: "GPa")
                ExpressionField(label: "Second moment I", text: $iText, unit: "mm⁴")
            }
            Section {
                ForEach($loads) { $load in
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("Type", selection: $load.kind) {
                            ForEach(LoadInput.Kind.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        ExpressionField(label: load.kind == .distributed ? "w" : (load.kind == .moment ? "M (clockwise)" : "P (down)"),
                                        text: $load.magnitude,
                                        unit: load.kind == .distributed ? "kN/m" : (load.kind == .moment ? "kN·m" : "kN"))
                        ExpressionField(label: load.kind == .distributed ? "From x" : "At x", text: $load.start, unit: "m")
                        if load.kind == .distributed {
                            ExpressionField(label: "To x", text: $load.end, unit: "m")
                        }
                    }
                }
                .onDelete { loads.remove(atOffsets: $0) }
                Button("Add Load", systemImage: "plus") {
                    loads.append(LoadInput(kind: .point, magnitude: "10", start: "0", end: lengthText))
                }
            } header: {
                Text("Loads")
            } footer: {
                Text(support == .cantilever ? "Fixed at x = 0, free at x = L." : "Pinned at x = 0, roller at x = L.")
            }
        }
    }
}

private struct BeamResultsView: View {
    let beam: Beam
    let results: Beam.Results
    var forPaper = false

    private func color(_ i: Int) -> Color { forPaper ? ChartPalette.paperColor(i) : ChartPalette.color(i) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(beam.support.rawValue) beam, L = \(fmt(beam.length, 6)) m").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                if beam.support == .simplySupported {
                    row("Left reaction", "\(fmt(results.reactionLeft / 1000, 6)) kN")
                    row("Right reaction", "\(fmt(results.reactionRight / 1000, 6)) kN")
                } else {
                    row("Wall reaction", "\(fmt(results.reactionLeft / 1000, 6)) kN")
                    row("Wall moment", "\(fmt(results.fixedMoment / 1000, 6)) kN·m")
                }
                let mm = results.maxMoment
                row("Max |moment|", "\(fmt(mm.value / 1000, 6)) kN·m at x = \(fmt(mm.x, 4)) m")
                row("Max |shear|", "\(fmt(results.maxShear / 1000, 6)) kN")
                if !results.deflection.isEmpty {
                    let d = results.maxDeflection
                    row("Max deflection", "\(fmt(d.value * 1000, 6)) mm at x = \(fmt(d.x, 4)) m  (L/\(fmt(beam.length / max(abs(d.value), 1e-300), 4)))")
                }
            }
            diagram("Shear V (kN)", results.shear.map { $0 / 1000 }, slot: 0)
            diagram("Bending moment M (kN·m)", results.moment.map { $0 / 1000 }, slot: 1)
            if !results.deflection.isEmpty {
                diagram("Deflection (mm, down)", results.deflection.map { -$0 * 1000 }, slot: 2)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).font(.callout.monospaced()).textSelection(.enabled)
        }
    }

    private struct Sample: Identifiable { var id: Int; var x: Double; var y: Double }

    private func diagram(_ title: String, _ ys: [Double], slot: Int) -> some View {
        let samples = zip(results.x, ys).enumerated().map { Sample(id: $0.offset, x: $0.element.0, y: $0.element.1) }
        let c = color(slot)
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Chart(samples) { s in
                AreaMark(x: .value("x (m)", s.x), y: .value(title, s.y))
                    .foregroundStyle(c.opacity(0.18))
                LineMark(x: .value("x (m)", s.x), y: .value(title, s.y))
                    .foregroundStyle(c)
                    .lineStyle(SwiftUI.StrokeStyle(lineWidth: 2))
            }
            .chartXScale(domain: 0...beam.length)
            .frame(height: 150)
        }
    }
}
