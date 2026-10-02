import SwiftUI
import UIKit

// MARK: - Library

struct FormulaLibraryView: View {
    @EnvironmentObject private var calc: CalculatorStore
    @State private var search = ""
    @State private var editing: Formula?
    @State private var creating: Formula?
    @State private var path: [UUID] = []

    private var filtered: [Formula] {
        guard !search.isEmpty else { return calc.allFormulas }
        return calc.allFormulas.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.category.localizedCaseInsensitiveContains(search)
                || $0.expression.localizedCaseInsensitiveContains(search) || $0.summary.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(calc.categories, id: \.self) { category in
                    let items = filtered.filter { $0.category == category }
                    if !items.isEmpty {
                        Section(category) {
                            ForEach(items) { f in
                                NavigationLink(value: f.id) { FormulaRow(formula: f) }
                                    .contextMenu { menu(for: f) }
                                    .swipeActions {
                                        if !f.isBuiltIn {
                                            Button("Delete", systemImage: "trash", role: .destructive) { calc.delete(f) }
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search formulas")
            .navigationTitle("Formulas")
            .navigationDestination(for: UUID.self) { id in
                if let f = calc.formula(id: id) {
                    FormulaRunView(formula: f)
                } else {
                    ContentUnavailableView("Formula Deleted", systemImage: "function")
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Formula", systemImage: "plus") {
                        creating = Formula(name: "", expression: "")
                    }
                }
            }
            .sheet(item: $editing) { f in FormulaEditorView(formula: f, isNew: false) }
            .sheet(item: $creating) { f in FormulaEditorView(formula: f, isNew: true) }
        }
    }

    @ViewBuilder
    private func menu(for f: Formula) -> some View {
        if f.isBuiltIn {
            Button("Duplicate & Edit", systemImage: "plus.square.on.square") { editing = calc.duplicate(f) }
        } else {
            Button("Edit", systemImage: "pencil") { editing = f }
            Button("Duplicate", systemImage: "plus.square.on.square") { _ = calc.duplicate(f) }
            Button("Delete", systemImage: "trash", role: .destructive) { calc.delete(f) }
        }
    }
}

struct FormulaRow: View {
    let formula: Formula
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(formula.name).font(.body.weight(.medium))
                if !formula.isBuiltIn {
                    Image(systemName: "person.fill").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(formula.lines.joined(separator: "   "))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Run

/// Auto-generated input form for a formula, with live results.
struct FormulaRunView: View {
    let formula: Formula
    var initialInputs: [String: String] = [:]

    @EnvironmentObject private var calc: CalculatorStore
    @Environment(\.basisNavigate) private var navigate
    @State private var inputs: [String: String] = [:]
    @State private var loaded = false
    @State private var editing: Formula?
    @State private var recorded = false
    /// Display units chosen per input/output ("" = the declared unit).
    @State private var inputUnits: [String: String] = [:]
    @State private var outputUnits: [String: String] = [:]

    private var engine: CalculatorEngine { calc.engine }
    private var inputNames: [String] { engine.inputs(of: formula) }

    /// Parsed input values; inputs may be expressions ("2*pi", "30°", "g0").
    private var parsedInputs: (values: [String: Double], errors: [String: String]) {
        var values: [String: Double] = [:], errors: [String: String] = [:]
        for name in inputNames {
            let text = (inputs[name] ?? "").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            do {
                var v = try engine.evaluate(expression: text, values: [:])
                // Convert from the unit picked in the form to the formula's unit.
                if let chosen = inputUnits[name], !chosen.isEmpty {
                    v = try UnitLibrary.convert(v, from: chosen, to: declaredUnit(name))
                }
                values[name] = v
            } catch {
                errors[name] = error.localizedDescription
            }
        }
        return (values, errors)
    }

    private var result: FormulaResult {
        engine.evaluate(formula, inputs: parsedInputs.values)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(formula.lines, id: \.self) { line in
                        Text(MathText.pretty(line))
                            .font(.system(.title3, design: .serif))
                            .textSelection(.enabled)
                    }
                    if !formula.summary.isEmpty {
                        Text(formula.summary).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Inputs") {
                if inputNames.isEmpty {
                    Text("This formula has no inputs.").foregroundStyle(.secondary)
                }
                ForEach(inputNames, id: \.self) { name in
                    InputRow(name: name, variable: formula.variable(name) ?? dependencyVariable(name),
                             text: binding(for: name), unit: unitBinding(name, in: $inputUnits),
                             placeholder: placeholder(for: name), error: parsedInputs.errors[name])
                }
            }

            Section("Results") {
                if let error = result.error {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                } else {
                    ForEach(result.outputs) { o in
                        HStack(alignment: .firstTextBaseline) {
                            Text(o.name).font(.title3.monospaced().weight(.semibold))
                            Text("=").foregroundStyle(.secondary)
                            if let v = o.value {
                                Text(NumberFormatting.format(displayValue(v, of: o)))
                                    .font(.title3.monospaced()).textSelection(.enabled)
                                if !o.unit.isEmpty { UnitMenu(declared: o.unit, selection: unitBinding(o.name, in: $outputUnits)) }
                            } else if let e = o.error {
                                Text(e.localizedDescription).font(.callout).foregroundStyle(.orange)
                            }
                            Spacer()
                        }
                    }
                }
                Button {
                    calc.run(formula, inputs: parsedInputs.values)
                    recorded = true
                } label: {
                    Label(recorded ? "Saved to History" : "Calculate & Save to History",
                          systemImage: recorded ? "checkmark.circle.fill" : "equal.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!result.isSuccess || result.outputs.isEmpty)
            }

            UnitCheckSection(formula: formula, engine: engine)
        }
        .navigationTitle(formula.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Copy Results", systemImage: "doc.on.doc") { UIPasteboard.general.string = resultText }
                    .disabled(!result.isSuccess)
                InsertIntoNotebookMenu(block: noteBlock) {
                    Label("Insert into Notebook", systemImage: "note.text.badge.plus")
                }
                Button(formula.isBuiltIn ? "Duplicate & Edit" : "Edit", systemImage: "pencil") {
                    editing = formula.isBuiltIn ? calc.duplicate(formula) : formula
                }
            }
        }
        .sheet(item: $editing) { f in FormulaEditorView(formula: f, isNew: false) }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            inputs = initialInputs
        }
        .onChange(of: inputs) { _, _ in recorded = false }
    }

    /// This run (inputs and chosen units) as a note card.
    private func noteBlock() -> CalculationBlock {
        var b = calc.formulaBlock(formula, inputs: inputs.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty })
        b.inputUnits = inputUnits.filter { !$0.value.isEmpty }
        b.outputUnits = outputUnits.filter { !$0.value.isEmpty }
        return b
    }

    private func unitBinding(_ name: String, in dict: Binding<[String: String]>) -> Binding<String> {
        Binding(get: { dict.wrappedValue[name] ?? "" }, set: { dict.wrappedValue[name] = $0 })
    }

    private func declaredUnit(_ name: String) -> String {
        (formula.variable(name) ?? dependencyVariable(name))?.unit ?? ""
    }

    /// An output value in the unit picked for it.
    private func displayValue(_ v: Double, of o: FormulaOutput) -> Double {
        guard let chosen = outputUnits[o.name], !chosen.isEmpty else { return v }
        return (try? UnitLibrary.convert(v, from: o.unit, to: chosen)) ?? v
    }

    private func displayUnit(_ o: FormulaOutput) -> String {
        if let chosen = outputUnits[o.name], !chosen.isEmpty { return chosen }
        return o.unit
    }

    private func binding(for name: String) -> Binding<String> {
        Binding(get: { inputs[name] ?? "" }, set: { inputs[name] = $0 })
    }

    /// Metadata for inputs that come from a formula this one depends on.
    private func dependencyVariable(_ name: String) -> FormulaVariable? {
        for f in calc.allFormulas { if let v = f.variable(name) { return v } }
        return nil
    }

    private func placeholder(for name: String) -> String {
        if let v = calc.variables.first(where: { $0.name == name }), case let .success(x) = calc.value(ofVariable: name) {
            return "\(NumberFormatting.format(x)) (variable \(v.name))"
        }
        if let d = (formula.variable(name) ?? dependencyVariable(name))?.defaultValue, !d.isEmpty { return "\(d) (default)" }
        return "value"
    }

    private var resultText: String {
        var lines = [formula.name]
        lines += inputNames.compactMap { n in parsedInputs.values[n].map { "\(n) = \(NumberFormatting.format($0)) \(declaredUnit(n))".trimmingCharacters(in: .whitespaces) } }
        lines += result.outputs.compactMap { o in o.value.map { "\(o.name) = \(NumberFormatting.format(displayValue($0, of: o))) \(displayUnit(o))".trimmingCharacters(in: .whitespaces) } }
        return lines.joined(separator: "\n")
    }
}

private struct InputRow: View {
    let name: String
    let variable: FormulaVariable?
    @Binding var text: String
    @Binding var unit: String
    let placeholder: String
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name).font(.title3.monospaced().weight(.semibold)).frame(minWidth: 44, alignment: .leading)
                TextField(placeholder, text: $text)
                    .font(.title3.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .tertiarySystemFill)))
                if let declared = variable?.unit, !declared.isEmpty {
                    UnitMenu(declared: declared, selection: $unit).frame(minWidth: 40, alignment: .leading)
                }
            }
            if let label = variable?.label, !label.isEmpty {
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Editor

/// Create or edit a formula. Variables are detected automatically as you type.
struct FormulaEditorView: View {
    @State var formula: Formula
    let isNew: Bool
    @EnvironmentObject private var calc: CalculatorStore
    @Environment(\.dismiss) private var dismiss
    @State private var newCategory = ""

    private var engine: CalculatorEngine {
        // Include the edited formula (replacing its saved version) so its own
        // outputs are known and dependency cycles are found.
        let others = calc.allFormulas.filter { $0.id != formula.id }
        return CalculatorEngine(angleMode: calc.angleMode, formulas: [formula] + others, variables: calc.variables)
    }

    private var validation: CalcError? {
        formula.lines.isEmpty ? nil : engine.validate(formula)
    }

    private var detectedInputs: [String] { validation == nil ? engine.inputs(of: formula) : [] }
    private var outputs: [String] { formula.outputNames }

    var body: some View {
        NavigationStack {
            Form {
                Section("Formula") {
                    TextField("Name (e.g. Kinetic Energy)", text: $formula.name)
                    Picker("Category", selection: $formula.category) {
                        ForEach(calc.categories, id: \.self) { Text($0).tag($0) }
                        if !calc.categories.contains(formula.category) { Text(formula.category).tag(formula.category) }
                    }
                    HStack {
                        TextField("New category", text: $newCategory)
                        Button("Add") {
                            let c = newCategory.trimmingCharacters(in: .whitespaces)
                            if !c.isEmpty { formula.category = c; newCategory = "" }
                        }
                        .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    TextField("Description (optional)", text: $formula.summary, axis: .vertical)
                }

                Section {
                    TextEditor(text: $formula.expression)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 110)
                } header: {
                    Text("Expression")
                } footer: {
                    if let validation {
                        Label(validation.localizedDescription, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    } else {
                        Text("One statement per line, e.g. KE = 0.5*m*v^2. You can use × ÷ ² √ π, functions like sin(θ), constants like g0, and outputs of other saved formulas (e.g. E = KE + PE).")
                    }
                }

                if !detectedInputs.isEmpty {
                    Section("Detected Variables") {
                        ForEach(detectedInputs, id: \.self) { name in
                            VariableMetadataRow(name: name, variable: metadataBinding(name), showsDefault: true)
                        }
                    }
                }
                if !outputs.isEmpty {
                    Section("Results") {
                        ForEach(outputs, id: \.self) { name in
                            VariableMetadataRow(name: name, variable: metadataBinding(name), showsDefault: false)
                        }
                    }
                }
                if validation == nil, !formula.lines.isEmpty {
                    UnitCheckSection(formula: formula, engine: engine)
                }
            }
            .navigationTitle(isNew ? "New Formula" : "Edit Formula")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(formula.name.trimmingCharacters(in: .whitespaces).isEmpty || formula.lines.isEmpty || validation != nil)
                }
            }
        }
    }

    private func metadataBinding(_ name: String) -> Binding<FormulaVariable> {
        Binding(
            get: { formula.variable(name) ?? FormulaVariable(name: name) },
            set: { newValue in
                if let i = formula.variables.firstIndex(where: { $0.name == name }) {
                    formula.variables[i] = newValue
                } else {
                    formula.variables.append(newValue)
                }
            })
    }

    private func save() {
        // Keep metadata only for names still used by the expression.
        let used = Set(detectedInputs + outputs)
        formula.variables.removeAll { !used.contains($0.name) }
        calc.save(formula)
        dismiss()
    }
}

private struct VariableMetadataRow: View {
    let name: String
    @Binding var variable: FormulaVariable
    let showsDefault: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(name).font(.body.monospaced().weight(.semibold)).frame(minWidth: 50, alignment: .leading)
            TextField("meaning", text: $variable.label)
            TextField("unit", text: $variable.unit)
                .frame(width: 80)
                .foregroundStyle(UnitLibrary.parse(variable.unit) == nil ? Color.red : Color.primary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if showsDefault {
                TextField("default", text: $variable.defaultValue)
                    .frame(width: 80)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }
}

// MARK: - History

struct HistoryView: View {
    @EnvironmentObject private var calc: CalculatorStore
    @Environment(\.basisNavigate) private var navigate
    @State private var search = ""
    @State private var confirmClear = false

    private var filtered: [CalculationRecord] {
        guard !search.isEmpty else { return calc.history }
        return calc.history.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.expression.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if calc.history.isEmpty {
                    ContentUnavailableView("No Calculations Yet", systemImage: "clock.arrow.circlepath",
                                           description: Text("Results from the calculator and formulas appear here."))
                } else {
                    List {
                        ForEach(filtered) { r in row(r) }
                            .onDelete { idx in calc.deleteHistory(Set(idx.map { filtered[$0].id })) }
                    }
                    .searchable(text: $search, prompt: "Search history")
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: CalculationRecord.self) { r in
                if let f = calc.formula(id: r.formulaID) {
                    FormulaRunView(formula: f, initialInputs: Dictionary(uniqueKeysWithValues: r.inputs.map { ($0.name, NumberFormatting.plain($0.value)) }))
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear History", systemImage: "trash", role: .destructive) { confirmClear = true }
                        .disabled(calc.history.isEmpty)
                }
            }
            .confirmationDialog("Clear all history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) { calc.clearHistory() }
            }
        }
    }

    @ViewBuilder
    private func row(_ r: CalculationRecord) -> some View {
        let content = VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(r.title).font(.headline)
                Spacer()
                Text(r.date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
            }
            if r.formulaID == nil {
                Text(r.expression).font(.callout.monospaced()).foregroundStyle(.secondary)
            } else if !r.inputs.isEmpty {
                Text(r.inputs.map { "\($0.name)=\(NumberFormatting.format($0.value))" }.joined(separator: ", "))
                    .font(.callout.monospaced()).foregroundStyle(.secondary)
            }
            Text(r.results.map { "\($0.name == "=" ? "" : "\($0.name) = ")\($0.formatted)" }.joined(separator: "    "))
                .font(.body.monospaced().weight(.semibold))
        }
        .padding(.vertical, 2)

        Group {
            if r.formulaID != nil, calc.formula(id: r.formulaID) != nil {
                NavigationLink(value: r) { content }
            } else {
                Button {
                    calc.draftExpression = r.expression
                    navigate(.calculator)
                } label: { content }
                .buttonStyle(.plain)
            }
        }
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text(for: r) }
            InsertIntoNotebookMenu(block: { calc.block(for: r) }) {
                Label("Insert into Notebook", systemImage: "note.text.badge.plus")
            }
            Button("Delete", systemImage: "trash", role: .destructive) { calc.deleteHistory([r.id]) }
        }
    }

    private func text(for r: CalculationRecord) -> String {
        var lines = [r.title]
        lines += r.inputs.map { "\($0.name) = \($0.formatted)" }
        lines += r.results.map { "\($0.name) = \($0.formatted)" }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Tools

/// Quick-access engineering tools. They are ordinary formulas run through
/// the same engine – no separate calculation code.
struct ToolsView: View {
    @EnvironmentObject private var calc: CalculatorStore

    private let featured: [(id: Int, icon: String)] = [
        (1, "x.squareroot"), (60, "bolt"), (20, "figure.run"), (23, "arrow.right.circle"), (26, "bolt.fill"),
        (27, "arrow.up.right"), (2, "triangle"), (24, "scalemass"), (40, "square.stack.3d.down.right"), (43, "gearshape.2"),
        (45, "ruler"), (63, "point.3.connected.trianglepath.dotted"),
    ]

    private func formula(_ n: Int) -> Formula? {
        BuiltInFormulas.all.first { $0.id.uuidString.hasSuffix(String(format: "%012ld", n)) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    NavigationLink {
                        UnitConverterView()
                    } label: {
                        card(icon: "arrow.left.arrow.right", title: "Unit Converter",
                             summary: "Length, force, energy, pressure, temperature and more — including compound units.")
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        FunctionGraphView()
                    } label: {
                        card(icon: "function", title: "Function Grapher",
                             summary: "Plot up to eight functions of x, trace values and add graphs to your notes.")
                    }
                    .buttonStyle(.plain)
                    ForEach(featured, id: \.id) { item in
                        if let f = formula(item.id) {
                            NavigationLink(value: f.id) {
                                card(icon: item.icon, title: f.name, summary: f.summary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(18)
            }
            .navigationTitle("Tools")
            .navigationDestination(for: UUID.self) { id in
                if let f = calc.formula(id: id) { FormulaRunView(formula: f) }
            }
        }
    }
}

extension ToolsView {
    fileprivate func card(icon: String, title: String, summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(.tint)
            Text(title).font(.headline).foregroundStyle(.primary)
            Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
    }
}

// MARK: - Settings

struct BasisSettingsView: View {
    @EnvironmentObject private var calc: CalculatorStore
    @State private var showAppearance = false
    @State private var showExportApp = false
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Calculator") {
                    Picker("Angle Unit", selection: $calc.angleMode) {
                        Text("Degrees").tag(AngleMode.degrees)
                        Text("Radians").tag(AngleMode.radians)
                    }
                }
                Section("Appearance") {
                    Button("Accent Color…", systemImage: "paintpalette") { showAppearance = true }
                }
                Section("Data") {
                    Button("Export Formulas, Variables & History…", systemImage: "square.and.arrow.up") {
                        shareURL = calc.exportData()
                    }
                    Button("Export App (.ipa)…", systemImage: "app.badge") { showExportApp = true }
                }
                Section {
                    LabeledContent("Version", value: "Basis 2.0 (Stage 6)")
                } footer: {
                    Text("Everything is stored on this iPad. Notes live in Files › On My iPad › Basis.")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showAppearance) { AppearanceSettingsView() }
            .sheet(isPresented: $showExportApp) { ExportView() }
            .sheet(item: Binding(get: { shareURL.map(SharedFile.init) }, set: { shareURL = $0?.url })) { f in
                ShareSheet(items: [f.url])
            }
        }
    }
}

private struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

// MARK: - Pretty math

enum MathText {
    /// Light typographic cleanup for display: * → ·, ^2 → ², sqrt → √.
    static func pretty(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "**", with: "^")
        t = t.replacingOccurrences(of: "*", with: "·")
        t = t.replacingOccurrences(of: "sqrt(", with: "√(")
        let sup: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"]
        var out = ""
        var chars = Array(t)[...]
        while let c = chars.first {
            chars = chars.dropFirst()
            if c == "^", let d = chars.first, let s = sup[d], chars.dropFirst().first.map({ !$0.isNumber && $0 != "." }) ?? true {
                out.append(s)
                chars = chars.dropFirst()
            } else {
                out.append(c)
            }
        }
        return out
    }
}
