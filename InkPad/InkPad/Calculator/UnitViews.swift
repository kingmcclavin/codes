import SwiftUI
import UIKit

// MARK: - Unit menu

/// Shows a unit; tapping it offers compatible units (m → mm, km, ft …).
/// Falls back to plain text for units with no alternatives.
struct UnitMenu: View {
    /// The unit the formula declares.
    let declared: String
    @Binding var selection: String

    private var options: [UnitDef] { UnitLibrary.compatibleUnits(with: declared) }

    var body: some View {
        let shown = selection.isEmpty ? declared : selection
        if options.count > 1 {
            Menu {
                Picker("Unit", selection: Binding(get: { shown }, set: { selection = $0 == declared ? "" : $0 })) {
                    ForEach(options) { u in
                        Text(u.symbol == u.name ? u.symbol : "\(u.symbol) — \(u.name)").tag(u.symbol)
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(shown)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .foregroundStyle(shown == declared ? Color.secondary : Color.accentColor)
            }
            .fixedSize()
        } else {
            Text(declared).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Unit check

/// Dimensional-analysis summary for a formula.
struct UnitCheckSection: View {
    let formula: Formula
    let engine: CalculatorEngine

    var body: some View {
        let report = UnitChecker(engine: engine).check(formula)
        if !report.inferred.isEmpty || !report.warnings.isEmpty {
            Section {
                ForEach(formula.outputNames.filter { report.inferred[$0] != nil }, id: \.self) { name in
                    LabeledContent {
                        Text(report.inferred[name] ?? "").font(.callout.monospaced())
                    } label: {
                        Text(name).font(.body.monospaced())
                    }
                }
                ForEach(report.warnings, id: \.self) { w in
                    Label(w, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                }
            } header: {
                Text("Units")
            } footer: {
                if report.isConsistent {
                    Label("Units are consistent.", systemImage: "checkmark.seal").font(.caption)
                }
            }
        }
    }
}

// MARK: - Converter

/// Standalone unit converter. Any compatible pair converts, including
/// compound units typed by hand (kg·m/s², J/(mol·K)).
struct UnitConverterView: View {
    @AppStorage("converterCategory") private var categoryRaw = UnitCategory.length.rawValue
    @AppStorage("converterFrom") private var from = "m"
    @AppStorage("converterTo") private var to = "ft"
    @State private var input = "1"
    @State private var customFrom = ""
    @State private var customTo = ""
    @EnvironmentObject private var calc: CalculatorStore

    private var category: UnitCategory { UnitCategory(rawValue: categoryRaw) ?? .length }
    private var units: [UnitDef] { UnitLibrary.units(in: category) }

    private var fromUnit: String { customFrom.trimmingCharacters(in: .whitespaces).isEmpty ? from : customFrom }
    private var toUnit: String { customTo.trimmingCharacters(in: .whitespaces).isEmpty ? to : customTo }

    private var inputValue: Result<Double, Error> {
        Result { try calc.engine.evaluate(expression: input, values: [:]) }
    }

    private var output: Result<Double, Error> {
        inputValue.flatMap { v in Result { try UnitLibrary.convert(v, from: fromUnit, to: toUnit) } }
    }

    var body: some View {
        Form {
            Section {
                Picker("Quantity", selection: $categoryRaw) {
                    ForEach(UnitCategory.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .onChange(of: categoryRaw) { _, _ in
                    let list = units
                    from = list.first?.symbol ?? ""
                    to = list.dropFirst().first?.symbol ?? from
                    customFrom = ""; customTo = ""
                }
            }

            Section("From") {
                HStack {
                    TextField("Value", text: $input)
                        .font(.title2.monospaced())
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    unitPicker($from)
                }
                if case let .failure(e) = inputValue, !input.isEmpty {
                    Text(e.localizedDescription).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    let (f, t, cf, ct) = (from, to, customFrom, customTo)
                    from = t; to = f
                    customFrom = ct; customTo = cf
                    if case let .success(v) = output { input = NumberFormatting.plain(v) }
                } label: {
                    Label("Swap", systemImage: "arrow.up.arrow.down").frame(maxWidth: .infinity)
                }
            }

            Section("To") {
                HStack {
                    switch output {
                    case let .success(v):
                        Text(NumberFormatting.format(v))
                            .font(.title2.monospaced().weight(.semibold))
                            .textSelection(.enabled)
                    case let .failure(e):
                        Text(e.localizedDescription).font(.callout).foregroundStyle(.orange)
                    }
                    Spacer()
                    unitPicker($to)
                }
                if case let .success(v) = output {
                    Button("Copy Result", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = "\(NumberFormatting.plain(v)) \(toUnit)"
                    }
                }
            }

            Section {
                TextField("From unit (e.g. kg·m/s²)", text: $customFrom)
                TextField("To unit (e.g. lbf)", text: $customTo)
            } header: {
                Text("Custom Units")
            } footer: {
                Text("Type any unit to override the pickers. Combine units with · * / ^ and parentheses, e.g. J/(mol·K), m^3/s, kN·m. Prefixes k, M, G, m, µ, n work on SI units.")
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Section("All \(category.rawValue) Units") {
                if case let .success(v) = inputValue {
                    ForEach(units.filter { UnitLibrary.parse($0.symbol)?.dimension == UnitLibrary.parse(fromUnit)?.dimension }) { u in
                        LabeledContent(u.name) {
                            if let x = try? UnitLibrary.convert(v, from: fromUnit, to: u.symbol) {
                                Text("\(NumberFormatting.format(x)) \(u.symbol)").font(.callout.monospaced())
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Unit Converter")
    }

    private func unitPicker(_ selection: Binding<String>) -> some View {
        Picker("Unit", selection: selection) {
            ForEach(units) { u in Text(u.symbol).tag(u.symbol) }
            if !units.contains(where: { $0.symbol == selection.wrappedValue }) {
                Text(selection.wrappedValue).tag(selection.wrappedValue)
            }
        }
        .labelsHidden()
        .fixedSize()
    }
}
