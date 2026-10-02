import XCTest
@testable import InkPad

final class ExpressionTests: XCTestCase {
    private func eval(_ s: String, _ mode: AngleMode = .radians, vars: [CalcVariable] = []) throws -> Double {
        try CalculatorEngine(angleMode: mode, variables: vars).evaluateLine(s).value
    }

    private func assertEval(_ s: String, _ expected: Double, _ mode: AngleMode = .radians, accuracy: Double = 1e-9,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(try eval(s, mode), expected, accuracy: accuracy, s, file: file, line: line)
    }

    private func assertError(_ s: String, _ expected: CalcError, _ mode: AngleMode = .radians,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try eval(s, mode), s, file: file, line: line) { error in
            XCTAssertEqual(error as? CalcError, expected, s, file: file, line: line)
        }
    }

    func testArithmeticAndPrecedence() {
        assertEval("2 + 3 * 4", 14)
        assertEval("(2 + 3) * 4", 20)
        assertEval("10 - 4 - 3", 3)
        assertEval("2 ^ 3 ^ 2", 512)
        assertEval("-2^2", -4)
        assertEval("2^-1", 0.5)
        assertEval("8 ÷ 2 × 4", 16)
        assertEval("3 − 5", -2)
        assertEval("2**10", 1024)
        assertEval("((1+2)*(3+4))", 21)
        assertEval("7 % ", 0.07)
        assertEval("5!", 120)
    }

    func testScientificNotationAndUnicode() {
        assertEval("1.5e3", 1500)
        assertEval("2E-3", 0.002)
        assertEval("6.02e23 / 1e23", 6.02)
        assertEval("3²", 9)
        assertEval("10⁻²", 0.01)
        assertEval("½ · 4", 2)
        assertEval("√16", 4)
        assertEval("√(9+16)", 5)
        assertEval("∛27", 3)
        assertEval("|−3|", 3)
    }

    func testImplicitMultiplication() {
        let vars = [CalcVariable(name: "a", expression: "2"), CalcVariable(name: "b", expression: "3"), CalcVariable(name: "c", expression: "4")]
        XCTAssertEqual(try eval("2a", vars: vars), 4)
        XCTAssertEqual(try eval("2(3+1)", vars: vars), 8)
        XCTAssertEqual(try eval("(1+1)(2+2)", vars: vars), 8)
        XCTAssertEqual(try eval("4ac", vars: vars), 32, "short lowercase names split into products")
        XCTAssertEqual(try eval("2π", vars: vars), 2 * .pi, accuracy: 1e-12)
        XCTAssertEqual(try eval("b²", vars: vars), 9)
    }

    func testFunctions() {
        assertEval("sqrt(25)", 5)
        assertEval("abs(-7)", 7)
        assertEval("log(1000)", 3)
        assertEval("ln(e)", 1)
        assertEval("exp(0)", 1)
        assertEval("log2(8)", 3)
        assertEval("logb(81, 3)", 4)
        assertEval("root(32, 5)", 2)
        assertEval("max(3, 9, 4)", 9)
        assertEval("avg(1, 2, 3, 4)", 2.5)
        assertEval("nCr(5, 2)", 10)
        assertEval("nPr(5, 2)", 20)
        assertEval("round(3.14159, 2)", 3.14)
        assertEval("mod(-7, 3)", 2)
        assertEval("(-8)^(1/3)", -2)
        assertEval("hypot(3, 4)", 5)
    }

    func testTrigDegreesAndRadians() {
        assertEval("sin(90)", 1, .degrees)
        assertEval("sin(90°)", 1, .degrees)
        assertEval("sin(90°)", 1, .radians)
        assertEval("cos(180)", -1, .degrees)
        assertEval("sin(30)", 0.5, .degrees, accuracy: 1e-12)
        assertEval("tan(45)", 1, .degrees, accuracy: 1e-12)
        assertEval("sin(π)", 0, .radians)
        assertEval("cos(π/3)", 0.5, .radians, accuracy: 1e-12)
        assertEval("asin(1)", 90, .degrees)
        assertEval("acos(0)", .pi / 2, .radians)
        assertEval("atan(1)", 45, .degrees, accuracy: 1e-12)
        assertEval("deg(π)", 180)
        assertEval("sin 30", 0.5, .degrees, accuracy: 1e-12)
    }

    func testErrors() {
        assertError("1/0", .divisionByZero)
        assertError("sqrt(-1)", .domain("Square root requires a non-negative value"))
        assertError("ln(0)", .domain("ln requires a positive value"))
        assertError("asin(2)", .domain("asin requires a value between -1 and 1"))
        assertError("tan(90)", .domain("tan is undefined at 90° + k·180°"), .degrees)
        assertError("2 + q", .missingVariable("q"))
        XCTAssertThrowsError(try eval("2 +")) { XCTAssertEqual(($0 as? CalcError).map { if case .invalidExpression = $0 { return true }; return false }, true) }
        XCTAssertThrowsError(try eval("(1 + 2"))
        XCTAssertThrowsError(try eval("1 + 2)"))
        XCTAssertThrowsError(try eval("3 # 4"))
        XCTAssertThrowsError(try eval("sin()"))
        XCTAssertThrowsError(try eval("1e999"))
        XCTAssertThrowsError(try eval(""))
    }

    func testVariablesAndAssignments() throws {
        let vars = [CalcVariable(name: "m", expression: "5"), CalcVariable(name: "v", expression: "10"),
                    CalcVariable(name: "KE", expression: "0.5*m*v^2")]
        XCTAssertEqual(try eval("KE", vars: vars), 250)
        let r = try CalculatorEngine(variables: vars).evaluateLine("p = m*v")
        XCTAssertEqual(r.target, "p")
        XCTAssertEqual(r.value, 50)
        // Variables may be angles and constants.
        XCTAssertEqual(try eval("sin(θ)", .radians, vars: [CalcVariable(name: "θ", expression: "30°")]), 0.5, accuracy: 1e-12)
        XCTAssertEqual(try eval("F", vars: [CalcVariable(name: "F", expression: "2*g0")]), 19.6133, accuracy: 1e-9)
    }

    func testCircularVariablesAreDetected() {
        let vars = [CalcVariable(name: "a", expression: "b + 1"), CalcVariable(name: "b", expression: "a + 1")]
        XCTAssertThrowsError(try eval("a", vars: vars)) { error in
            guard case .circularDependency? = error as? CalcError else { return XCTFail("\(error)") }
        }
    }

    func testFormatting() {
        XCTAssertEqual(NumberFormatting.format(0.1 + 0.2), "0.3")
        XCTAssertEqual(NumberFormatting.format(250), "250")
        XCTAssertEqual(NumberFormatting.format(-3), "-3")
        XCTAssertEqual(NumberFormatting.format(6.674e-11), "6.674 × 10⁻¹¹")
        XCTAssertEqual(NumberFormatting.plain(1.5e-7), "1.5e-7")
    }
}

final class FormulaTests: XCTestCase {
    private func builtIn(_ name: String) -> Formula { BuiltInFormulas.all.first { $0.name == name }! }
    private let engine = CalculatorEngine(angleMode: .degrees, formulas: BuiltInFormulas.all)

    func testAllBuiltInFormulasParseAndHaveNoCycles() {
        for f in BuiltInFormulas.all {
            XCTAssertNil(engine.validate(f), f.name)
            XCTAssertFalse(engine.inputs(of: f).isEmpty, f.name)
        }
    }

    func testQuadraticFormula() {
        let q = builtIn("Quadratic Formula")
        XCTAssertEqual(engine.inputs(of: q), ["a", "b", "c"])
        let r = engine.evaluate(q, inputs: ["a": 2, "b": 5, "c": -3])
        XCTAssertTrue(r.isSuccess)
        XCTAssertEqual(r.outputs.map(\.name), ["x₁", "x₂"])
        XCTAssertEqual(r.outputs[0].value!, 0.5, accuracy: 1e-12)
        XCTAssertEqual(r.outputs[1].value!, -3, accuracy: 1e-12)
    }

    func testQuadraticWithComplexRootsReportsDomainError() {
        let r = engine.evaluate(builtIn("Quadratic Formula"), inputs: ["a": 1, "b": 0, "c": 1])
        XCTAssertEqual(r.outputs.first?.error, .domain("Square root requires a non-negative value"))
    }

    func testMissingVariable() {
        let r = engine.evaluate(builtIn("Quadratic Formula"), inputs: ["a": 1, "b": 2])
        XCTAssertEqual(r.outputs.first?.error, .missingVariable("c"))
    }

    func testKineticEnergyWithUnits() {
        let ke = builtIn("Kinetic Energy")
        let r = engine.evaluate(ke, inputs: ["m": 2, "v": 25])
        XCTAssertEqual(r.outputs.first?.value, 625)
        XCTAssertEqual(r.outputs.first?.unit, "J")
    }

    func testDefaultValues() {
        let pe = builtIn("Potential Energy")
        let r = engine.evaluate(pe, inputs: ["m": 10, "h": 2])
        XCTAssertEqual(r.outputs.first?.value ?? 0, 196.133, accuracy: 1e-9, "g defaults to 9.80665")
    }

    func testFormulaDependencies() {
        let total = builtIn("Mechanical Energy")
        XCTAssertEqual(Set(engine.inputs(of: total)), ["m", "v", "g", "h"])
        let r = engine.evaluate(total, inputs: ["m": 2, "v": 3, "h": 1])
        XCTAssertEqual(r.outputs.first?.value ?? 0, 9 + 19.6133, accuracy: 1e-9)
    }

    func testUserFormulaDependencyAndCycleDetection() {
        let a = Formula(name: "A", expression: "A1 = B1 + 1")
        let b = Formula(name: "B", expression: "B1 = A1 * 2")
        let engine = CalculatorEngine(formulas: [a, b])
        XCTAssertEqual(engine.validate(a), .circularDependency(["A", "B", "A"]))
        let r = engine.evaluate(a, inputs: [:])
        guard case .circularDependency? = r.error else { return XCTFail("expected cycle, got \(r)") }

        let ke = Formula(name: "KE", expression: "KE = 0.5*m*v^2")
        let total = Formula(name: "Total", expression: "TotalEnergy = KE + PE2", variables: [])
        let pe = Formula(name: "PE2", expression: "PE2 = m*9.81*h")
        let e2 = CalculatorEngine(formulas: [ke, total, pe])
        XCTAssertEqual(e2.evaluate(total, inputs: ["m": 1, "v": 2, "h": 1]).outputs.first?.value ?? 0, 2 + 9.81, accuracy: 1e-9)
    }

    func testDeclaredVariablesAreNotResolvedThroughOtherFormulas() {
        // The quadratic's `c` must not be computed by a user formula that outputs `c`.
        let hyp = Formula(name: "Hyp", expression: "c = √(a² + b²)")
        let engine = CalculatorEngine(formulas: [hyp] + BuiltInFormulas.all)
        XCTAssertEqual(engine.inputs(of: builtIn("Quadratic Formula")), ["a", "b", "c"])
    }

    func testMultiLineFormulaUsesEarlierResults() {
        let f = builtIn("Projectile Motion")
        let r = engine.evaluate(f, inputs: ["v0": 20, "θ": 45])
        XCTAssertTrue(r.isSuccess, "\(r.outputs.map { "\($0.name): \(String(describing: $0.error))" })")
        let range = r.outputs.first { $0.name == "R" }!.value!
        XCTAssertEqual(range, 400 / 9.80665, accuracy: 1e-6)
    }

    func testSyntaxErrorIsReportedNotThrown() {
        let bad = Formula(name: "Bad", expression: "y = (2 + ")
        XCTAssertNotNil(CalculatorEngine(formulas: [bad]).evaluate(bad, inputs: [:]).error)
    }

    func testFormulaCodingIsTolerant() throws {
        let json = #"{"name": "Old", "expression": "y = 2x"}"#.data(using: .utf8)!
        let f = try JSONDecoder().decode(Formula.self, from: json)
        XCTAssertEqual(f.name, "Old")
        XCTAssertEqual(f.category, "Custom")
        XCTAssertEqual(CalculatorEngine(formulas: [f]).evaluate(f, inputs: ["x": 3]).outputs.first?.value, 6)
    }

    @MainActor
    func testStorePersistsFormulasVariablesAndHistory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = CalculatorStore(directory: dir)
        try store.evaluate("m = 5")
        try store.evaluate("v = 10")
        XCTAssertEqual(try store.evaluate("0.5*m*v^2").value, 250)
        store.save(Formula(name: "Mine", expression: "y = 2x"))
        store.flush()   // writes are asynchronous
        let reopened = CalculatorStore(directory: dir)
        XCTAssertEqual(reopened.variables.map(\.name), ["m", "v"])
        XCTAssertEqual(reopened.userFormulas.map(\.name), ["Mine"])
        XCTAssertEqual(reopened.history.count, 3)
    }
}
