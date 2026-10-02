import SwiftUI

// MARK: - Card editor

/// Creates or edits a calculation card in a note: pick a saved formula or
/// type expressions, fill in inputs (with units) and see the live result.
struct CalculationCardEditor: View {
    @State var block: CalculationBlock
    let isNew: Bool
    let onCommit: (CalculationBlock, String) -> Void

    @EnvironmentObject private var calc: CalculatorStore
    @Environment(\.dismiss) private var dismiss
    @State private var choosingFormula = false
    @State private var search = ""

    private enum Source: Hashable { case expression, formula }

    private var engine: CalculatorEngine { calc.engine(for: block) }
    private var evaluation: CalculationBlock.Evaluation { block.evaluate(engine: engine) }
    private var validation: CalcError? { block.formula.lines.isEmpty ? nil : engine.validate(block.formula) }

    private var source: Binding<Source> {
        Binding(
            get: { block.isAdHoc && !choosingFormula ? .expression : .formula },
            set: { newValue in
                switch newValue {
                case .expression:
                    choosingFormula = false
                    if !block.isAdHoc { block = .expression("") }
                case .formula:
                    if block.isAdHoc { choosingFormula = true }
                }
            })
    }

    var body: some View {
        NavigationStack {
            Form {
                if isNew {
                    Section {
                        Picker("Source", selection: source) {
                            Text("Expression").tag(Source.expression)
                            Text("Formula").tag(Source.formula)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                if choosingFormula {
                    formulaChooser
                } else {
                    definition
                    if validation == nil && !block.formula.lines.isEmpty {
                        inputsSection
                        resultsSection
                        optionsSection
                        previewSection
                    }
                }
            }
            .navigationTitle(isNew ? "Insert Calculation" : "Edit Calculation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Insert" : "Done") {
                        onCommit(block, calc.renderedText(block))
                        dismiss()
                    }
                    .bold()
                    .disabled(choosingFormula || block.formula.lines.isEmpty || validation != nil)
                }
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var definition: some View {
        if block.isAdHoc {
            Section {
                TextField("Title (optional)", text: Binding(
                    get: { block.formula.name == CalculationBlock.adHocName ? "" : block.formula.name },
                    set: {
                        block.formula.name = $0.isEmpty ? CalculationBlock.adHocName : $0
                        block.showsTitle = !$0.isEmpty
                    }))
                TextEditor(text: $block.formula.expression)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(minHeight: 90)
            } header: {
                Text("Expression")
            } footer: {
                if let validation {
                    Label(validation.localizedDescription, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                } else {
                    Text("One line per step, e.g. 2·sin(30°) or F = m·a. Unknown names become inputs below; calculator variables and saved formulas work too.")
                }
            }
        } else {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(block.formula.name).font(.headline)
                    ForEach(block.formula.lines, id: \.self) { line in
                        Text(MathText.pretty(line)).font(.system(.body, design: .serif))
                    }
                }
                if let latest = calc.formula(id: block.libraryID),
                   latest.expression != block.formula.expression || latest.variables != block.formula.variables {
                    Button("Update to Latest Version", systemImage: "arrow.triangle.2.circlepath") { block.formula = latest }
                }
                if isNew {
                    Button("Choose Another Formula", systemImage: "function") { choosingFormula = true }
                }
            } header: {
                Text("Formula")
            }
        }
    }

    private var inputsSection: some View {
        Section("Inputs") {
            let ev = evaluation
            if ev.inputNames.isEmpty {
                Text("No inputs needed.").foregroundStyle(.secondary)
            }
            ForEach(ev.inputNames, id: \.self) { name in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(name).font(.body.monospaced().weight(.semibold)).frame(minWidth: 44, alignment: .leading)
                        TextField(placeholder(name), text: binding(\.inputs, name))
                            .font(.body.monospaced())
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        let declared = block.declaredUnit(name, engine: engine)
                        if !declared.isEmpty {
                            UnitMenu(declared: declared, selection: binding(\.inputUnits, name))
                        }
                    }
                    if let label = (block.formula.variable(name) ?? dependencyVariable(name))?.label, !label.isEmpty {
                        Text(label).font(.caption).foregroundStyle(.secondary)
                    }
                    if let e = ev.inputErrors[name] {
                        Text(e).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private var resultsSection: some View {
        Section("Results") {
            let ev = evaluation
            if let e = ev.result.error {
                Label(e.localizedDescription, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            ForEach(ev.result.outputs) { o in
                HStack(alignment: .firstTextBaseline) {
                    Text(o.name).font(.body.monospaced().weight(.semibold))
                    Text("=").foregroundStyle(.secondary)
                    let d = block.display(o)
                    if let v = d.value {
                        Text(NumberFormatting.format(v)).font(.body.monospaced())
                        if !o.unit.isEmpty {
                            UnitMenu(declared: o.unit, selection: binding(\.outputUnits, o.name))
                        }
                    } else if let e = o.error {
                        Text(e.localizedDescription).font(.callout).foregroundStyle(.orange)
                    }
                    Spacer()
                }
            }
        }
    }

    private var optionsSection: some View {
        Section("Show on Page") {
            Toggle("Title", isOn: $block.showsTitle)
            Toggle("Formula Lines", isOn: $block.showsExpression)
        }
    }

    private var previewSection: some View {
        Section("Preview") {
            Text(calc.renderedText(block))
                .font(.system(.callout, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.06)))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 3)
                }
        }
    }

    private var formulaChooser: some View {
        Section {
            TextField("Search formulas", text: $search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            ForEach(filteredFormulas) { f in
                Button {
                    block = calc.formulaBlock(f)
                    choosingFormula = false
                    search = ""
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.name).foregroundStyle(.primary)
                        Text("\(f.category) · \(f.lines.joined(separator: "   "))")
                            .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        } header: {
            Text("Choose a Formula")
        }
    }

    private var filteredFormulas: [Formula] {
        let all = calc.allFormulas
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.category.localizedCaseInsensitiveContains(search)
                || $0.expression.localizedCaseInsensitiveContains(search)
        }
    }

    // MARK: Helpers

    private func binding(_ key: WritableKeyPath<CalculationBlock, [String: String]>, _ name: String) -> Binding<String> {
        Binding(get: { block[keyPath: key][name] ?? "" }, set: { block[keyPath: key][name] = $0 })
    }

    private func dependencyVariable(_ name: String) -> FormulaVariable? {
        for f in calc.allFormulas { if let v = f.variable(name) { return v } }
        return nil
    }

    private func placeholder(_ name: String) -> String {
        if case let .success(x) = calc.value(ofVariable: name) { return "\(NumberFormatting.format(x)) (variable)" }
        if let d = (block.formula.variable(name) ?? dependencyVariable(name))?.defaultValue, !d.isEmpty { return "\(d) (default)" }
        return "value"
    }
}

// MARK: - Insert into a notebook

/// Menu listing open and recent notebooks; picking one opens it and offers
/// the calculation for insertion on the current page.
struct InsertIntoNotebookMenu<MenuLabel: View>: View {
    let block: () -> CalculationBlock
    @ViewBuilder let label: () -> MenuLabel

    @EnvironmentObject private var calc: CalculatorStore
    @EnvironmentObject private var tabs: TabsModel
    @EnvironmentObject private var store: DocumentStore

    var body: some View {
        Menu {
            let open = tabs.tabs
            if !open.isEmpty {
                Section("Open Notebooks") {
                    ForEach(open, id: \.self) { id in
                        Button(tabs.title(for: id), systemImage: "book") { insert(into: id) }
                    }
                }
            }
            let recent = Array(store.summaries.filter { !open.contains($0.id) }
                .sorted { $0.modifiedAt > $1.modifiedAt }.prefix(8))
            if !recent.isEmpty {
                Section("Recent") {
                    ForEach(recent) { d in
                        Button(d.title.isEmpty ? "Untitled" : d.title, systemImage: "doc") { insert(into: d.id) }
                    }
                }
            }
            if open.isEmpty && recent.isEmpty {
                Text("Create a notebook first")
            }
        } label: {
            label()
        }
    }

    private func insert(into id: UUID) {
        calc.pendingInsertion = block()
        tabs.open(id)
    }
}
