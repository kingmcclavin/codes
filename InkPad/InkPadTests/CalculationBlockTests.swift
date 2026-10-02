import XCTest
@testable import InkPad

final class CalculationBlockTests: XCTestCase {
    private func engine(for block: CalculationBlock, variables: [CalcVariable] = []) -> CalculatorEngine {
        CalculationBlock.engine(for: block, angleMode: .degrees, library: BuiltInFormulas.all, variables: variables)
    }

    private var kineticEnergy: Formula { BuiltInFormulas.all.first { $0.name == "Kinetic Energy" }! }

    func testBareExpression() {
        let b = CalculationBlock.expression("2 + 3")
        XCTAssertEqual(b.renderText(engine: engine(for: b)), "2 + 3 = 5")
    }

    func testFormulaCard() {
        let b = CalculationBlock(formula: kineticEnergy, libraryID: kineticEnergy.id, inputs: ["m": "2", "v": "3"])
        let text = b.renderText(engine: engine(for: b))
        XCTAssertTrue(text.hasPrefix("Kinetic Energy\n"), text)
        XCTAssertTrue(text.contains("m = 2 kg,  v = 3 m/s"), text)
        XCTAssertTrue(text.hasSuffix("KE = 9 J"), text)
    }

    func testUnitsOnCards() {
        var b = CalculationBlock(formula: kineticEnergy, libraryID: kineticEnergy.id, inputs: ["m": "2000", "v": "3"])
        b.inputUnits["m"] = "g"          // 2000 g = 2 kg
        b.outputUnits["KE"] = "kJ"
        let ev = b.evaluate(engine: engine(for: b))
        XCTAssertEqual(ev.values["m"] ?? 0, 2, accuracy: 1e-12)
        let text = b.renderText(engine: engine(for: b))
        XCTAssertTrue(text.contains("m = 2000 g"), text)
        XCTAssertTrue(text.hasSuffix("KE = 0.009 kJ"), text)
    }

    func testMissingInputsAndDefaults() {
        let pe = BuiltInFormulas.all.first { $0.name == "Potential Energy" }!
        let b = CalculationBlock(formula: pe, libraryID: pe.id, inputs: ["m": "1"])
        let text = b.renderText(engine: engine(for: b))
        XCTAssertTrue(text.contains("g = 9.80665"), text)   // default shown
        XCTAssertTrue(text.contains("h = ?"), text)
        XCTAssertTrue(text.hasSuffix("PE = ?"), text)
    }

    func testAdHocLinesWithInputs() {
        var b = CalculationBlock.expression("F = m*a\nW = F*d")
        b.inputs = ["m": "2", "a": "3", "d": "4"]
        let text = b.renderText(engine: engine(for: b))
        XCTAssertTrue(text.contains("F = 6"), text)
        XCTAssertTrue(text.hasSuffix("W = 24"), text)
        XCTAssertFalse(text.contains(CalculationBlock.adHocName), text)
    }

    func testSyntaxErrorDoesNotCrash() {
        let b = CalculationBlock.expression("2 + * (")
        XCTAssertTrue(b.renderText(engine: engine(for: b)).contains("⚠︎"))
    }

    func testCardSurvivesDeletedLibraryFormula() {
        var custom = Formula(name: "Area", expression: "A = w*h", variables: [FormulaVariable(name: "A", unit: "m²")])
        custom.isBuiltIn = false
        let b = CalculationBlock(formula: custom, libraryID: custom.id, inputs: ["w": "2", "h": "5"])
        // The library no longer contains the formula; the snapshot still works.
        let e = CalculationBlock.engine(for: b, angleMode: .degrees, library: [], variables: [])
        XCTAssertTrue(b.renderText(engine: e).hasSuffix("A = 10 m²"))
    }

    func testCodableRoundTripAndBackwardCompatibility() throws {
        var b = CalculationBlock(formula: kineticEnergy, libraryID: kineticEnergy.id, inputs: ["m": "2"])
        b.outputUnits["KE"] = "kJ"
        let element = TextElement(text: "x", style: TextStyle(), box: BoxGeometry(rect: CGRect(x: 0, y: 0, width: 100, height: 20)),
                                  calculation: b)
        let data = try JSONEncoder().encode(CanvasElement.text(element))
        guard case let .text(decoded) = try JSONDecoder().decode(CanvasElement.self, from: data) else { return XCTFail() }
        XCTAssertEqual(decoded.calculation, b)

        // Plain text saved before calculation cards existed.
        let plain = TextElement(text: "hello", style: TextStyle(), box: BoxGeometry(rect: .zero))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as! [String: Any]
        json.removeValue(forKey: "calculation")
        let old = try JSONDecoder().decode(TextElement.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.calculation)
        XCTAssertEqual(old.text, "hello")
    }

    func testCardLayoutKeepsTopLeft() {
        let b = CalculationBlock.expression("1 + 1")
        let style = TextElement.calculationStyle(color: .black)
        let first = TextElement.calculationCard(b, text: "1 + 1 = 2", at: CGPoint(x: 200, y: 200), style: style, maxWidth: 500)
        XCTAssertNotNil(first.calculation)
        let topLeft = CGPoint(x: first.box.center.x - first.box.size.width / 2, y: first.box.center.y - first.box.size.height / 2)
        let longer = TextElement.calculationCard(b, text: "1 + 1 = 2\nmore lines here\nand here", existing: first, style: style, maxWidth: 500)
        XCTAssertEqual(longer.id, first.id)
        XCTAssertGreaterThan(longer.box.size.height, first.box.size.height)
        XCTAssertEqual(longer.box.center.x - longer.box.size.width / 2, topLeft.x, accuracy: 0.01)
        XCTAssertEqual(longer.box.center.y - longer.box.size.height / 2, topLeft.y, accuracy: 0.01)
        XCTAssertTrue(longer.bounds.contains(longer.box.boundingRect))
    }
}
