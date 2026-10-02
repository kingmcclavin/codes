import Foundation
import SwiftUI

/// App-wide calculator state: saved formulas, variables, history and
/// settings, persisted as small versioned JSON files (works offline, no
/// server). All calculation work is delegated to `CalculatorEngine`.
@MainActor
final class CalculatorStore: ObservableObject {
    static let shared = CalculatorStore()

    @Published private(set) var userFormulas: [Formula] = []
    @Published private(set) var variables: [CalcVariable] = []
    @Published private(set) var history: [CalculationRecord] = []
    @Published var angleMode: AngleMode {
        didSet { UserDefaults.standard.set(angleMode.rawValue, forKey: "angleMode") }
    }
    @Published private(set) var ans: Double?

    /// A calculation waiting to be inserted into the active note.
    @Published var pendingInsertion: CalculationRecord?

    private let directory: URL
    private let ioQueue = DispatchQueue(label: "Basis.calculator.io", qos: .utility)
    /// Text in the calculator's input line (shared so History can reopen it).
    @Published var draftExpression = ""
    private static let formatVersion = 1
    private static let maxHistory = 500

    init(directory: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.directory = directory ?? base.appendingPathComponent("Basis", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        angleMode = AngleMode(rawValue: UserDefaults.standard.string(forKey: "angleMode") ?? "") ?? .degrees
        userFormulas = load([Formula].self, "formulas.json") ?? []
        variables = load([CalcVariable].self, "variables.json") ?? []
        history = load([CalculationRecord].self, "history.json") ?? []
    }

    // MARK: Engine

    var allFormulas: [Formula] { userFormulas + BuiltInFormulas.all }

    var engine: CalculatorEngine {
        CalculatorEngine(angleMode: angleMode, formulas: allFormulas, variables: variables, ans: ans)
    }

    func formula(id: UUID?) -> Formula? {
        guard let id else { return nil }
        return allFormulas.first { $0.id == id }
    }

    var categories: [String] {
        var result = BuiltInFormulas.categories
        for f in userFormulas where !result.contains(f.category) { result.append(f.category) }
        if !result.contains("Custom") { result.append("Custom") }
        return result
    }

    // MARK: Calculator lines

    /// Evaluates a calculator line; assignments create/update variables.
    @discardableResult
    func evaluate(_ text: String) throws -> LineResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try engine.evaluateLine(trimmed)
        ans = result.value
        if let target = result.target, let parts = CalculatorEngine.splitAssignment(trimmed) {
            setVariable(CalcVariable(name: target, expression: parts.expression,
                                     unit: variables.first { $0.name == target }?.unit ?? ""))
        }
        record(CalculationRecord(title: result.target.map { "\($0) =" } ?? "Calculation", expression: trimmed,
                                 results: [NamedValue(name: result.target ?? "=", value: result.value)]))
        return result
    }

    // MARK: Variables

    func setVariable(_ v: CalcVariable) {
        if let i = variables.firstIndex(where: { $0.name == v.name }) { variables[i] = v } else { variables.append(v) }
        save(variables, "variables.json")
    }

    func deleteVariable(_ name: String) {
        variables.removeAll { $0.name == name }
        save(variables, "variables.json")
    }

    func value(ofVariable name: String) -> Result<Double, CalcError> {
        do { return .success(try engine.value(ofVariable: name)) } catch let e as CalcError { return .failure(e) } catch {
            return .failure(.invalidExpression("\(error)"))
        }
    }

    // MARK: Formulas

    func save(_ formula: Formula) {
        var f = formula
        f.isBuiltIn = false
        f.exportsOutputs = true
        if let i = userFormulas.firstIndex(where: { $0.id == f.id }) { userFormulas[i] = f } else { userFormulas.append(f) }
        save(userFormulas, "formulas.json")
    }

    func delete(_ formula: Formula) {
        userFormulas.removeAll { $0.id == formula.id }
        save(userFormulas, "formulas.json")
    }

    func duplicate(_ formula: Formula) -> Formula {
        var copy = formula
        copy.id = UUID()
        copy.name = formula.name + (formula.isBuiltIn ? "" : " Copy")
        copy.isBuiltIn = false
        if formula.isBuiltIn && copy.category == formula.category { copy.category = "Custom" }
        save(copy)
        return copy
    }

    /// Runs a formula and records it in the history.
    @discardableResult
    func run(_ formula: Formula, inputs: [String: Double], recordInHistory: Bool = true) -> FormulaResult {
        let result = engine.evaluate(formula, inputs: inputs)
        if recordInHistory, result.error == nil, !result.outputs.contains(where: { $0.value == nil }) {
            let names = engine.inputs(of: formula)
            let inputValues = names.compactMap { n in inputs[n].map { NamedValue(name: n, value: $0, unit: formula.unit(of: n)) } }
            let outputs = result.outputs.compactMap { o in o.value.map { NamedValue(name: o.name, value: $0, unit: o.unit) } }
            ans = outputs.last?.value ?? ans
            record(CalculationRecord(title: formula.name, formulaID: formula.id, expression: formula.expression,
                                     inputs: inputValues, results: outputs))
        }
        return result
    }

    // MARK: History

    func record(_ r: CalculationRecord) {
        // Collapse identical consecutive runs (e.g. pressing Calculate twice).
        if let last = history.first, last.title == r.title, last.inputs == r.inputs, last.results == r.results { return }
        history.insert(r, at: 0)
        if history.count > Self.maxHistory { history.removeLast(history.count - Self.maxHistory) }
        save(history, "history.json")
    }

    func deleteHistory(_ ids: Set<UUID>) {
        history.removeAll { ids.contains($0.id) }
        save(history, "history.json")
    }

    func clearHistory() {
        history.removeAll()
        save(history, "history.json")
    }

    // MARK: Persistence (versioned)

    /// Blocks until all pending writes are on disk (app backgrounding, tests).
    func flush() {
        ioQueue.sync {}
    }

    private struct Envelope<T: Codable>: Codable {
        var version: Int
        var items: T
    }

    private func save<T: Codable>(_ items: T, _ file: String) {
        let url = directory.appendingPathComponent(file)
        let envelope = Envelope(version: Self.formatVersion, items: items)
        ioQueue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(envelope) { try? data.write(to: url, options: .atomic) }
        }
    }

    private func load<T: Codable>(_ type: T.Type, _ file: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(file)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Envelope<T>.self, from: data))?.items
    }

    /// JSON export of formulas, variables and history.
    func exportData() -> URL? {
        struct Export: Codable {
            var formulas: [Formula]
            var variables: [CalcVariable]
            var history: [CalculationRecord]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Export(formulas: userFormulas, variables: variables, history: history)) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Basis Calculator Data.json")
        return (try? data.write(to: url, options: .atomic)) == nil ? nil : url
    }
}
