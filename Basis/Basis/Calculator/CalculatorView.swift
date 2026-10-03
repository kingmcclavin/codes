import SwiftUI
import UIKit

/// Lets any Basis screen switch the sidebar section (e.g. History → Calculator).
private struct BasisNavigateKey: EnvironmentKey {
    static let defaultValue: (SidebarItem) -> Void = { _ in }
}

extension EnvironmentValues {
    var basisNavigate: (SidebarItem) -> Void {
        get { self[BasisNavigateKey.self] }
        set { self[BasisNavigateKey.self] = newValue }
    }
}

/// The calculator screen: a friendly keypad, the tape of recent answers,
/// and extras (variables, constants, save as formula) in one menu.
struct CalculatorView: View {
    @EnvironmentObject private var calc: CalculatorStore
    @State private var showVariables = false
    @State private var newFormula: Formula?

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > 760 {
                HStack(spacing: 0) {
                    tape
                    Divider()
                    CalculatorPad()
                        .frame(width: min(460, geo.size.width * 0.5))
                        .padding(20)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            } else {
                VStack(spacing: 0) {
                    tape
                    CalculatorPad()
                        .padding(16)
                }
            }
        }
        .navigationTitle("Calculator")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Variables…", systemImage: "x.squareroot") { showVariables = true }
                    Button("Save as Formula…", systemImage: "square.and.arrow.down") { saveAsFormula() }
                        .disabled(saveableExpression == nil)
                    NavigationLink {
                        UnitConverterView()
                    } label: {
                        Label("Unit Converter", systemImage: "arrow.left.arrow.right")
                    }
                    Divider()
                    Button("Clear Tape", systemImage: "trash", role: .destructive) {
                        calc.deleteHistory(Set(calc.history.filter { $0.formulaID == nil }.map(\.id)))
                    }
                    .disabled(calculatorHistory.isEmpty)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showVariables) {
            NavigationStack {
                VariablesPanel()
                    .navigationTitle("Variables")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showVariables = false } } }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $newFormula) { f in
            FormulaEditorView(formula: f, isNew: true)
        }
    }

    // MARK: Tape

    private var calculatorHistory: [CalculationRecord] {
        Array(calc.history.filter { $0.formulaID == nil }.prefix(40).reversed())
    }

    private var tape: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .trailing, spacing: 14) {
                    if calculatorHistory.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "plus.forwardslash.minus").font(.largeTitle).foregroundStyle(.tertiary)
                            Text("Your answers will appear here.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text("Tip: type m = 5 to save a variable you can reuse.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                    ForEach(calculatorHistory) { r in
                        Button {
                            calc.draftExpression = r.expression
                        } label: {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(MathText.pretty(r.expression))
                                    .font(.system(.callout, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Text(r.results.first.map { NumberFormatting.format($0.value) } ?? "")
                                    .font(.system(.title2, design: .rounded).weight(.medium))
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Copy Result", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = r.results.first.map { NumberFormatting.plain($0.value) }
                            }
                            Button("Use Again", systemImage: "arrow.down.doc") { calc.draftExpression = r.expression }
                            InsertIntoNotebookMenu(block: { calc.expressionBlock(r.expression) }) {
                                Label("Insert into Notebook", systemImage: "note.text.badge.plus")
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) { calc.deleteHistory([r.id]) }
                        }
                        .id(r.id)
                    }
                }
                .padding(20)
            }
            .onChange(of: calc.history.first?.id) { _, _ in
                if let last = calculatorHistory.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .onAppear {
                if let last = calculatorHistory.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var saveableExpression: String? {
        let t = calc.draftExpression.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { return t }
        return calculatorHistory.last?.expression
    }

    private func saveAsFormula() {
        guard let t = saveableExpression else { return }
        let expression = CalculatorEngine.splitAssignment(t) == nil ? "result = \(t)" : t
        newFormula = Formula(name: "New Formula", expression: expression)
    }
}

struct FunctionPicker: View {
    let onPick: (String) -> Void
    var body: some View {
        List(MathFunctions.catalog, id: \.name) { f in
            Button { onPick(f.insert) } label: {
                HStack {
                    Text(f.name).font(.body.monospaced()).foregroundStyle(.primary)
                    Spacer()
                    Text(f.help).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 360, height: 460)
    }
}

struct ConstantsPicker: View {
    let onPick: (String) -> Void
    var body: some View {
        List(Constants.all) { c in
            Button { onPick(c.id) } label: {
                HStack {
                    Text(c.symbol).font(.title3.monospaced()).frame(width: 44, alignment: .leading)
                    VStack(alignment: .leading) {
                        Text(c.name).foregroundStyle(.primary)
                        Text("\(c.id) = \(NumberFormatting.format(c.value)) \(c.unit)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(width: 380, height: 480)
    }
}

/// Calculator variables: define once (`m = 5`), reuse everywhere.
struct VariablesPanel: View {
    @EnvironmentObject private var calc: CalculatorStore
    @State private var editing: CalcVariable?
    @State private var adding = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Variables").font(.headline)
                Spacer()
                Button("Add Variable", systemImage: "plus") { adding = true }
                    .labelStyle(.iconOnly)
            }
            .padding(12)
            Divider()
            if calc.variables.isEmpty {
                ContentUnavailableView("No Variables", systemImage: "x.squareroot",
                                       description: Text("Type m = 5 in the calculator, or tap +."))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(calc.variables) { v in
                        Button {
                            calc.draftExpression += v.name
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(v.name).font(.body.monospaced().weight(.semibold)).foregroundStyle(.primary)
                                    if Double(v.expression) == nil {
                                        Text(v.expression).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                Text(valueText(v)).font(.body.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editing = v }
                            Button("Delete", systemImage: "trash", role: .destructive) { calc.deleteVariable(v.name) }
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { calc.deleteVariable(v.name) }
                            Button("Edit", systemImage: "pencil") { editing = v }.tint(.indigo)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(item: $editing) { v in VariableEditor(variable: v) }
        .sheet(isPresented: $adding) { VariableEditor(variable: nil) }
    }

    private func valueText(_ v: CalcVariable) -> String {
        switch calc.value(ofVariable: v.name) {
        case let .success(x): return NumberFormatting.format(x) + (v.unit.isEmpty ? "" : " \(v.unit)")
        case .failure: return "—"
        }
    }
}

struct VariableEditor: View {
    let variable: CalcVariable?
    @EnvironmentObject private var calc: CalculatorStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var expression = ""
    @State private var unit = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. m)", text: $name)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(variable != nil)
                    TextField("Value or expression (e.g. 5, 2.1e3, 30°, m*g0)", text: $expression)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Unit (optional, e.g. kg)", text: $unit)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text(status)
                }
            }
            .navigationTitle(variable == nil ? "New Variable" : "Edit \(variable!.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        calc.setVariable(CalcVariable(name: name.trimmingCharacters(in: .whitespaces),
                                                      expression: expression.trimmingCharacters(in: .whitespaces), unit: unit))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let variable { name = variable.name; expression = variable.expression; unit = variable.unit }
            }
        }
    }

    private var isValid: Bool {
        guard let tokens = try? Lexer.tokenize(name), tokens.count == 1, case .identifier = tokens[0] else { return false }
        return (try? calc.engine.evaluate(expression: expression, values: [:])) != nil
    }

    private var status: String {
        if !name.isEmpty, (try? Lexer.tokenize(name)).map({ $0.count == 1 }) != true { return "Names start with a letter and contain no spaces." }
        guard !expression.isEmpty else { return "Variables can hold numbers, angles (30°), scientific notation (6.02e23), constants or expressions of other variables." }
        do {
            let v = try calc.engine.evaluate(expression: expression, values: [:])
            return "= \(NumberFormatting.format(v))"
        } catch {
            return error.localizedDescription
        }
    }
}
