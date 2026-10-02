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

/// Modern scientific calculator: expression line with live result, tape,
/// scientific keypad, variables panel, constants and functions.
struct CalculatorView: View {
    @EnvironmentObject private var calc: CalculatorStore
    @State private var error: String?
    @State private var showConstants = false
    @State private var showFunctions = false
    @State private var newFormula: Formula?
    @FocusState private var inputFocused: Bool

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > 820 {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        tape
                        Divider()
                        inputArea
                        keypad.padding(12)
                    }
                    Divider()
                    VariablesPanel()
                        .frame(width: 320)
                }
            } else {
                VStack(spacing: 0) {
                    tape
                    Divider()
                    inputArea
                    keypad.padding(10)
                    Divider()
                    VariablesPanel()
                        .frame(height: 220)
                }
            }
        }
        .navigationTitle("Calculator")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Angle", selection: $calc.angleMode) {
                    ForEach(AngleMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                NavigationLink {
                    UnitConverterView()
                } label: {
                    Label("Unit Converter", systemImage: "arrow.left.arrow.right")
                }
                Button("Save as Formula", systemImage: "square.and.arrow.down") { saveAsFormula() }
                    .disabled(calc.draftExpression.trimmingCharacters(in: .whitespaces).isEmpty)
            }
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
                LazyVStack(alignment: .trailing, spacing: 10) {
                    if calculatorHistory.isEmpty {
                        Text("Type an expression like 2 + 3·4, sin(30°) or m = 5, then press =.\nVariables you define can be reused anywhere.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    ForEach(calculatorHistory) { r in
                        Button {
                            calc.draftExpression = r.expression
                        } label: {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(r.expression)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text("= " + (r.results.first.map { NumberFormatting.format($0.value) } ?? ""))
                                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Copy Result", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = r.results.first.map { NumberFormatting.plain($0.value) }
                            }
                            Button("Use Expression", systemImage: "arrow.down.doc") { calc.draftExpression = r.expression }
                        }
                        .id(r.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: calc.history.first?.id) { _, _ in
                if let last = calculatorHistory.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .onAppear {
                if let last = calculatorHistory.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Input

    private var preview: (text: String, isError: Bool)? {
        let t = calc.draftExpression.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        do {
            let r = try calc.engine.evaluateLine(t)
            return ((r.target.map { "\($0) = " } ?? "= ") + NumberFormatting.format(r.value), false)
        } catch let e as CalcError {
            // Unfinished input is normal while typing; only show missing names and domain errors.
            switch e {
            case .missingVariable, .domain, .divisionByZero, .circularDependency, .unknownFunction, .argumentCount:
                return (e.localizedDescription, true)
            default:
                return nil
            }
        } catch {
            return nil
        }
    }

    private var inputArea: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextField("Expression", text: $calc.draftExpression, axis: .vertical)
                .font(.system(size: 26, weight: .regular, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .lineLimit(1...4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.numbersAndPunctuation)
                .focused($inputFocused)
                .onSubmit(evaluate)
            HStack {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if let p = preview {
                    Text(p.text)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(p.isError ? Color.orange : Color.secondary)
                }
                Spacer()
                Text(calc.angleMode.label)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground))
        .onChange(of: calc.draftExpression) { _, _ in error = nil }
    }

    private func evaluate() {
        let t = calc.draftExpression.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        do {
            try calc.evaluate(t)
            calc.draftExpression = ""
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveAsFormula() {
        let t = calc.draftExpression.trimmingCharacters(in: .whitespaces)
        let expression = CalculatorEngine.splitAssignment(t) == nil ? "result = \(t)" : t
        newFormula = Formula(name: "New Formula", expression: expression)
    }

    // MARK: Keypad

    private func insert(_ s: String) {
        calc.draftExpression += s
        error = nil
    }

    private var keypad: some View {
        let rows: [[(String, KeyStyle, () -> Void)]] = [
            [("x²", .function, { insert("²") }), ("xʸ", .function, { insert("^") }), ("√", .function, { insert("√(") }),
             ("(", .function, { insert("(") }), (")", .function, { insert(")") }), ("⌫", .clear, backspace), ("AC", .clear, { calc.draftExpression = "" })],
            [("sin", .function, { insert("sin(") }), ("cos", .function, { insert("cos(") }), ("tan", .function, { insert("tan(") }),
             ("7", .digit, { insert("7") }), ("8", .digit, { insert("8") }), ("9", .digit, { insert("9") }), ("÷", .op, { insert("÷") })],
            [("sin⁻¹", .function, { insert("asin(") }), ("cos⁻¹", .function, { insert("acos(") }), ("tan⁻¹", .function, { insert("atan(") }),
             ("4", .digit, { insert("4") }), ("5", .digit, { insert("5") }), ("6", .digit, { insert("6") }), ("×", .op, { insert("×") })],
            [("log", .function, { insert("log(") }), ("ln", .function, { insert("ln(") }), ("eˣ", .function, { insert("exp(") }),
             ("1", .digit, { insert("1") }), ("2", .digit, { insert("2") }), ("3", .digit, { insert("3") }), ("−", .op, { insert("-") })],
            [("π", .function, { insert("π") }), ("e", .function, { insert("e") }), ("|x|", .function, { insert("abs(") }),
             ("0", .digit, { insert("0") }), (".", .digit, { insert(".") }), ("EE", .digit, { insert("E") }), ("+", .op, { insert("+") })],
            [("ans", .function, { insert("ans") }), ("°", .function, { insert("°") }), ("n!", .function, { insert("!") }),
             ("x=", .function, { insert(" = ") }), (",", .digit, { insert(", ") }), ("f(x)", .function, { showFunctions = true }), ("=", .equals, evaluate)],
        ]
        return Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(rows.indices, id: \.self) { r in
                GridRow {
                    ForEach(rows[r].indices, id: \.self) { c in
                        let key = rows[r][c]
                        KeyButton(title: key.0, style: key.1, action: key.2)
                            .popover(isPresented: key.0 == "f(x)" ? $showFunctions : .constant(false)) {
                                FunctionPicker { insert($0); showFunctions = false }
                            }
                    }
                }
            }
            GridRow {
                Button { showConstants = true } label: {
                    Label("Constants", systemImage: "atom").frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.bordered)
                .gridCellColumns(7)
                .popover(isPresented: $showConstants) {
                    ConstantsPicker { insert($0); showConstants = false }
                }
            }
        }
        .frame(maxWidth: 640)
    }

    private func backspace() {
        guard !calc.draftExpression.isEmpty else { return }
        calc.draftExpression.removeLast()
    }
}

enum KeyStyle { case digit, op, function, clear, equals }

private struct KeyButton: View {
    let title: String
    let style: KeyStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(style == .digit ? .title2.weight(.medium) : .body.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(background))
                .foregroundStyle(foreground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var background: Color {
        switch style {
        case .digit: return Color(uiColor: .secondarySystemBackground)
        case .op: return Color.appAccent.opacity(0.18)
        case .function: return Color(uiColor: .tertiarySystemFill)
        case .clear: return Color.red.opacity(0.14)
        case .equals: return Color.appAccent
        }
    }

    private var foreground: Color {
        switch style {
        case .equals: return .white
        case .op: return Color.appAccent
        case .clear: return .red
        default: return .primary
        }
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
