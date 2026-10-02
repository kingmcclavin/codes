import Foundation

// MARK: - Models

/// Metadata for a symbol used in a formula (input or output).
struct FormulaVariable: Codable, Hashable, Identifiable {
    var name: String
    /// What the symbol means, e.g. "mass".
    var label: String = ""
    /// Unit symbol, e.g. "kg" (see `UnitLibrary`).
    var unit: String = ""
    /// Optional default (an expression, e.g. "9.81" or "g0").
    var defaultValue: String = ""

    var id: String { name }
}

/// A saved, reusable calculation. `expression` holds one statement per line:
///
///     x₁ = (-b + √(b² - 4ac)) / (2a)
///     x₂ = (-b - √(b² - 4ac)) / (2a)
///
/// Input variables are detected automatically.
struct Formula: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var category: String = "Custom"
    var summary: String = ""
    var expression: String
    var variables: [FormulaVariable] = []
    var isBuiltIn = false
    /// Whether other formulas may use this formula's outputs by name
    /// (e.g. `E = KE + PE`). Always on for user formulas.
    var exportsOutputs = true

    init(id: UUID = UUID(), name: String, category: String = "Custom", summary: String = "", expression: String,
         variables: [FormulaVariable] = [], isBuiltIn: Bool = false, exportsOutputs: Bool = true) {
        self.id = id; self.name = name; self.category = category; self.summary = summary
        self.expression = expression; self.variables = variables
        self.isBuiltIn = isBuiltIn; self.exportsOutputs = exportsOutputs
    }

    private enum CodingKeys: String, CodingKey { case id, name, category, summary, expression, variables, isBuiltIn, exportsOutputs }

    // Tolerant decoding so saved formulas survive future model changes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Formula"
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "Custom"
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        expression = try c.decodeIfPresent(String.self, forKey: .expression) ?? ""
        variables = try c.decodeIfPresent([FormulaVariable].self, forKey: .variables) ?? []
        isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        exportsOutputs = try c.decodeIfPresent(Bool.self, forKey: .exportsOutputs) ?? true
    }

    var lines: [String] {
        expression.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// Names assigned by the formula (`name = …`), in order.
    var outputNames: [String] {
        lines.compactMap { line in
            guard let tokens = try? Lexer.tokenize(line), tokens.count > 2,
                  case let .identifier(name) = tokens[0], tokens[1] == .equals else { return nil }
            return name
        }
    }

    func variable(_ name: String) -> FormulaVariable? { variables.first { $0.name == name } }
    func unit(of name: String) -> String { variable(name)?.unit ?? "" }
}

/// A user variable in the calculator (`m = 5`, `F = m*a`). Stored as an
/// expression so dependent variables update when their inputs change.
struct CalcVariable: Codable, Hashable, Identifiable {
    var name: String
    var expression: String
    var unit: String = ""
    var id: String { name }
}

struct NamedValue: Codable, Hashable, Identifiable {
    var name: String
    var value: Double
    var unit: String = ""
    var id: String { name }

    var formatted: String {
        let v = NumberFormatting.format(value)
        return unit.isEmpty ? v : "\(v) \(unit)"
    }
}

/// One entry of the calculation history.
struct CalculationRecord: Codable, Hashable, Identifiable {
    var id = UUID()
    var date = Date()
    var title: String
    var formulaID: UUID?
    /// The source: a calculator line or the formula's expression.
    var expression: String
    var inputs: [NamedValue] = []
    var results: [NamedValue]
}

struct FormulaOutput: Identifiable {
    var name: String
    var value: Double?
    var error: CalcError?
    var unit: String
    var id: String { name }
}

struct FormulaResult {
    var outputs: [FormulaOutput]
    /// Set when nothing could be evaluated (e.g. a syntax error).
    var error: CalcError?

    var isSuccess: Bool { error == nil && outputs.allSatisfy { $0.error == nil } }
}

/// Result of a calculator line.
struct LineResult: Equatable {
    var target: String?
    var value: Double
}

// MARK: - Engine

/// Pure calculation engine: parsing, variable resolution, formula
/// dependencies and cycle detection. No UI or persistence.
struct CalculatorEngine {
    var angleMode: AngleMode
    let formulas: [Formula]
    let variables: [CalcVariable]
    var ans: Double?

    init(angleMode: AngleMode = .radians, formulas: [Formula] = [], variables: [CalcVariable] = [], ans: Double? = nil) {
        self.angleMode = angleMode
        self.formulas = formulas
        self.variables = variables
        self.ans = ans
        knownNames = Self.collectKnownNames(formulas: formulas, variables: variables)
    }

    /// Names that the parser must keep whole (never split `ac` → a·c).
    private(set) var knownNames: Set<String>

    private static func collectKnownNames(formulas: [Formula], variables: [CalcVariable]) -> Set<String> {
        var names = Set(variables.map(\.name))
        for f in formulas {
            names.formUnion(f.outputNames)
            names.formUnion(f.variables.map(\.name))
        }
        return names
    }

    private func parser(for formula: Formula? = nil) -> ExpressionParser {
        var known = knownNames
        if let formula {
            known.formUnion(formula.variables.map(\.name))
            known.formUnion(formula.outputNames)
        }
        return ExpressionParser(knownNames: known)
    }

    /// The formula that defines `name`, preferring user formulas.
    func formula(producing name: String, excluding: UUID? = nil) -> Formula? {
        let candidates = formulas.filter { $0.id != excluding && $0.exportsOutputs && $0.outputNames.contains(name) }
        return candidates.first { !$0.isBuiltIn } ?? candidates.first
    }

    // MARK: Parsing & analysis

    func parse(_ formula: Formula) throws -> [Statement] {
        let p = parser(for: formula)
        let statements = try formula.lines.enumerated().map { i, line -> Statement in
            do { return try p.parseStatement(line) } catch let e as CalcError {
                if formula.lines.count > 1, case let .invalidExpression(m) = e {
                    throw CalcError.invalidExpression("line \(i + 1): \(m)")
                }
                throw e
            }
        }
        guard !statements.isEmpty else { throw CalcError.invalidExpression("the formula is empty") }
        return statements
    }

    /// Input variables a formula needs, in order of appearance. Names produced
    /// by other saved formulas are expanded into *their* inputs.
    func inputs(of formula: Formula) -> [String] {
        var result: [String] = []
        collectInputs(formula, visiting: [], into: &result)
        // Declared variables first, in their declared order (a, b, c).
        let declared = formula.variables.map(\.name)
        return result.enumerated().sorted { l, r in
            let li = declared.firstIndex(of: l.element) ?? declared.count + l.offset
            let ri = declared.firstIndex(of: r.element) ?? declared.count + r.offset
            return li < ri
        }.map(\.element)
    }

    private func collectInputs(_ formula: Formula, visiting: Set<UUID>, into result: inout [String]) {
        guard let statements = try? parse(formula) else { return }
        var locals = Set<String>()
        for s in statements {
            for name in s.expression.variables where !locals.contains(name) && !result.contains(name) {
                if Constants.isConstant(name) || name == "ans" { continue }
                if let dep = self.formula(producing: name, excluding: formula.id), !visiting.contains(dep.id),
                   !formula.variables.contains(where: { $0.name == name }) {
                    collectInputs(dep, visiting: visiting.union([formula.id]), into: &result)
                } else {
                    result.append(name)
                }
            }
            if let t = s.target { locals.insert(t) }
        }
    }

    /// Other saved formulas this formula depends on (direct).
    func dependencies(of formula: Formula) -> [Formula] {
        guard let statements = try? parse(formula) else { return [] }
        var locals = Set<String>(), deps: [Formula] = []
        for s in statements {
            for name in s.expression.variables where !locals.contains(name) {
                if let dep = self.formula(producing: name, excluding: formula.id), !deps.contains(where: { $0.id == dep.id }) {
                    deps.append(dep)
                }
            }
            if let t = s.target { locals.insert(t) }
        }
        return deps
    }

    /// Syntax and dependency-cycle check, for the formula editor.
    func validate(_ formula: Formula) -> CalcError? {
        do { _ = try parse(formula) } catch let e as CalcError { return e } catch { return .invalidExpression("\(error)") }
        var path: [Formula] = []
        func visit(_ f: Formula) -> CalcError? {
            if let i = path.firstIndex(where: { $0.id == f.id }) {
                return .circularDependency(path[i...].map(\.name) + [f.name])
            }
            path.append(f)
            defer { path.removeLast() }
            for d in dependencies(of: f) {
                if let e = visit(d) { return e }
            }
            return nil
        }
        return visit(formula)
    }

    // MARK: Evaluation

    /// Evaluates a formula with the given input values. Missing inputs fall
    /// back to calculator variables, then to the variable's default value.
    func evaluate(_ formula: Formula, inputs: [String: Double]) -> FormulaResult {
        if let e = validate(formula), case .circularDependency = e {
            return FormulaResult(outputs: [], error: e)
        }
        let statements: [Statement]
        do { statements = try parse(formula) } catch let e as CalcError {
            return FormulaResult(outputs: [], error: e)
        } catch {
            return FormulaResult(outputs: [], error: .invalidExpression("\(error)"))
        }
        let scope = Scope(engine: self, values: inputs)
        scope.formulaStack = [formula.id]
        scope.declared = Set(formula.variables.map(\.name))
        var outputs: [FormulaOutput] = []
        scope.applyDefaults(of: formula)
        for (i, s) in statements.enumerated() {
            let name = s.target ?? (statements.count == 1 ? "Result" : "Line \(i + 1)")
            do {
                let v = try scope.evaluate(s.expression)
                if let t = s.target { scope.values[t] = v }
                outputs.append(FormulaOutput(name: name, value: v, error: nil, unit: formula.unit(of: name)))
            } catch let e as CalcError {
                outputs.append(FormulaOutput(name: name, value: nil, error: e, unit: formula.unit(of: name)))
            } catch {
                outputs.append(FormulaOutput(name: name, value: nil, error: .invalidExpression("\(error)"), unit: ""))
            }
        }
        return FormulaResult(outputs: outputs, error: nil)
    }

    /// Evaluates one calculator line (`2+3`, `m = 5`, `KE`).
    func evaluateLine(_ text: String) throws -> LineResult {
        let statement = try parser().parseStatement(text)
        let scope = Scope(engine: self, values: [:])
        if let t = statement.target {
            scope.variableStack = [t]   // `x = x + 1` is a cycle, not recursion
        }
        let value = try scope.evaluate(statement.expression)
        return LineResult(target: statement.target, value: value)
    }

    /// Evaluates a standalone expression with explicit values (tools, graphs, tables).
    func evaluate(expression text: String, values: [String: Double]) throws -> Double {
        let e = try parser().parseExpression(text)
        return try Scope(engine: self, values: values).evaluate(e)
    }

    /// Current value of a calculator variable.
    func value(ofVariable name: String) throws -> Double {
        let scope = Scope(engine: self, values: [:])
        return try scope.evaluate(.variable(name))
    }

    /// Splits `name = expr` into its parts, for storing variables.
    static func splitAssignment(_ text: String) -> (name: String, expression: String)? {
        guard let eq = text.firstIndex(of: "=") else { return nil }
        let name = text[..<eq].trimmingCharacters(in: .whitespaces)
        let expr = text[text.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !expr.isEmpty, let tokens = try? Lexer.tokenize(name), tokens.count == 1,
              case .identifier = tokens[0] else { return nil }
        return (name, expr)
    }
}

/// Name resolution during one evaluation.
private final class Scope {
    let engine: CalculatorEngine
    var values: [String: Double]
    var formulaStack: [UUID] = []
    var variableStack: [String] = []
    /// Inputs declared by the formula being evaluated; never looked up in
    /// other formulas (a quadratic's `c` is not the Pythagorean `c`).
    var declared: Set<String> = []

    init(engine: CalculatorEngine, values: [String: Double]) {
        self.engine = engine
        self.values = values
    }

    func evaluate(_ e: Expr) throws -> Double {
        try ExpressionEvaluator(angleMode: engine.angleMode, resolve: { [unowned self] in try self.lookup($0) }).evaluate(e)
    }

    func applyDefaults(of formula: Formula) {
        for v in formula.variables where !v.defaultValue.isEmpty && values[v.name] == nil
            && !engine.variables.contains(where: { $0.name == v.name }) {
            if let e = try? ExpressionParser().parseExpression(v.defaultValue), let x = try? evaluate(e) {
                values[v.name] = x
            }
        }
    }

    func lookup(_ name: String) throws -> Double? {
        if let v = values[name] { return v }
        if name == "ans" { return engine.ans }

        // Calculator variables (may themselves be expressions).
        if let variable = engine.variables.first(where: { $0.name == name }) {
            if variableStack.contains(name) {
                throw CalcError.circularDependency(variableStack + [name])
            }
            variableStack.append(name)
            defer { variableStack.removeLast() }
            let e = try ExpressionParser(knownNames: engine.knownNames).parseExpression(variable.expression)
            let v = try evaluate(e)
            values[name] = v
            return v
        }

        if let c = Constants.value(name) { return c }

        // Another saved formula produces this name.
        if !declared.contains(name), let formula = engine.formula(producing: name, excluding: nil) {
            if formulaStack.contains(formula.id) {
                let names = formulaStack.compactMap { id in engine.formulas.first { $0.id == id }?.name }
                throw CalcError.circularDependency(names + [formula.name])
            }
            formulaStack.append(formula.id)
            defer { formulaStack.removeLast() }
            applyDefaults(of: formula)
            for s in try engine.parse(formula) {
                let v = try evaluate(s.expression)
                if let t = s.target {
                    values[t] = v
                    if t == name { return v }
                }
            }
        }
        return nil
    }
}
