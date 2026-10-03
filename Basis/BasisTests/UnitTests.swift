import XCTest
@testable import Basis

final class UnitTests: XCTestCase {
    private func assertConvert(_ v: Double, _ from: String, _ to: String, _ expected: Double, accuracy: Double = 1e-9,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(try UnitLibrary.convert(v, from: from, to: to), expected, accuracy: accuracy,
                       "\(v) \(from) → \(to)", file: file, line: line)
    }

    func testSimpleConversions() {
        assertConvert(1, "km", "m", 1000)
        assertConvert(12, "in", "ft", 1)
        assertConvert(1, "mi", "km", 1.609344)
        assertConvert(1, "lb", "kg", 0.45359237)
        assertConvert(1, "kWh", "J", 3.6e6)
        assertConvert(1, "atm", "kPa", 101.325)
        assertConvert(1, "ksi", "psi", 1000, accuracy: 1e-6)
        assertConvert(36, "km/h", "m/s", 10)
        assertConvert(180, "°", "rad", .pi)
        assertConvert(1, "L", "mL", 1000)
    }

    func testTemperature() {
        assertConvert(100, "°C", "°F", 212)
        assertConvert(32, "°F", "°C", 0, accuracy: 1e-9)
        assertConvert(0, "°C", "K", 273.15)
        assertConvert(-40, "°C", "°F", -40)
        assertConvert(300, "K", "degC", 26.85, accuracy: 1e-9)
    }

    func testCompoundParsing() throws {
        let newton = try XCTUnwrap(UnitLibrary.parse("N")).dimension
        XCTAssertEqual(UnitLibrary.parse("kg·m/s²")?.dimension, newton)
        XCTAssertEqual(UnitLibrary.parse("kg*m/s^2")?.dimension, newton)
        XCTAssertEqual(UnitLibrary.parse("kg m s^-2")?.dimension, newton)
        XCTAssertEqual(UnitLibrary.parse("J/(mol·K)")?.dimension, UnitLibrary.parse("kg·m²/(s²·mol·K)")?.dimension)
        XCTAssertEqual(UnitLibrary.parse("1/s")?.dimension, UnitLibrary.parse("Hz")?.dimension)
        XCTAssertEqual(try XCTUnwrap(UnitLibrary.parse("kN·m")).scale, 1000, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(UnitLibrary.parse("µs")).scale, 1e-6, accuracy: 1e-18)
        XCTAssertEqual(try XCTUnwrap(UnitLibrary.parse("mm^3")).scale, 1e-9, accuracy: 1e-21)
        XCTAssertEqual(UnitLibrary.parse(""), .one)
        XCTAssertNil(UnitLibrary.parse("furlongs"))
        XCTAssertNil(UnitLibrary.parse("kg//m"))
        XCTAssertNil(UnitLibrary.parse("(m"))
        assertConvert(1, "kN·m", "lbf·ft", 737.5621492772654, accuracy: 1e-6)
        assertConvert(1, "g/cm³", "kg/m^3", 1000)
    }

    func testIncompatibleUnitsThrow() {
        XCTAssertThrowsError(try UnitLibrary.convert(1, from: "m", to: "s"))
        XCTAssertThrowsError(try UnitLibrary.convert(1, from: "kg", to: "nonsense"))
    }

    func testCompatibleUnits() {
        let lengths = UnitLibrary.compatibleUnits(with: "m").map(\.symbol)
        XCTAssertTrue(lengths.contains("ft"))
        XCTAssertTrue(lengths.contains("km"))
        XCTAssertFalse(lengths.contains("s"))
        // Energy first, then torque (same dimension).
        let energy = UnitLibrary.compatibleUnits(with: "J").map(\.symbol)
        XCTAssertEqual(energy.first, "J")
        XCTAssertTrue(energy.contains("kWh"))
        // Hand-written compound units are offered alongside the library ones.
        XCTAssertEqual(UnitLibrary.compatibleUnits(with: "kg·m/s²").first?.symbol, "kg·m/s²")
        XCTAssertTrue(UnitLibrary.compatibleUnits(with: "kg·m/s²").contains { $0.symbol == "N" })
        XCTAssertTrue(UnitLibrary.compatibleUnits(with: "bogus").isEmpty)
    }

    func testDimensionDescription() {
        XCTAssertEqual(UnitLibrary.parse("J")?.dimension.description, "kg·m²/s² (J)")
        XCTAssertEqual(UnitLibrary.parse("m")?.dimension.description, "m")
        XCTAssertEqual(UnitDimension.none.description, "dimensionless")
    }

    // MARK: Checker

    func testCheckerInfersKineticEnergy() throws {
        let engine = CalculatorEngine(formulas: BuiltInFormulas.all)
        let ke = try XCTUnwrap(BuiltInFormulas.all.first { $0.name == "Kinetic Energy" })
        let report = UnitChecker(engine: engine).check(ke)
        XCTAssertEqual(report.inferred["KE"], "kg·m²/s² (J)")
        XCTAssertTrue(report.isConsistent, report.warnings.joined(separator: "\n"))
    }

    func testCheckerFlagsMismatches() {
        let engine = CalculatorEngine()
        let wrongResult = Formula(name: "Wrong", expression: "F = m*v", variables: [
            FormulaVariable(name: "m", unit: "kg"), FormulaVariable(name: "v", unit: "m/s"), FormulaVariable(name: "F", unit: "N"),
        ])
        XCTAssertFalse(UnitChecker(engine: engine).check(wrongResult).isConsistent)

        let badSum = Formula(name: "Sum", expression: "x = d + t", variables: [
            FormulaVariable(name: "d", unit: "m"), FormulaVariable(name: "t", unit: "s"),
        ])
        let report = UnitChecker(engine: engine).check(badSum)
        XCTAssertEqual(report.warnings.count, 1)
        XCTAssertTrue(report.warnings[0].hasPrefix("x: "), report.warnings[0])

        let unknown = Formula(name: "Unknown", expression: "y = 2*q", variables: [FormulaVariable(name: "q", unit: "zorks")])
        XCTAssertTrue(UnitChecker(engine: engine).check(unknown).warnings.contains { $0.contains("zorks") })
    }

    func testCheckerUsesDependencyUnits() throws {
        let engine = CalculatorEngine(formulas: BuiltInFormulas.all)
        let mech = try XCTUnwrap(BuiltInFormulas.all.first { $0.name == "Mechanical Energy" })
        let report = UnitChecker(engine: engine).check(mech)
        XCTAssertEqual(report.inferred["E"], "kg·m²/s² (J)")
        XCTAssertTrue(report.isConsistent, report.warnings.joined(separator: "\n"))
    }

    /// Every unit used by a built-in formula must be understood by the library.
    func testBuiltInUnitsAreKnown() {
        for f in BuiltInFormulas.all {
            for v in f.variables where !v.unit.isEmpty {
                XCTAssertNotNil(UnitLibrary.parse(v.unit), "\(f.name): \(v.name) [\(v.unit)]")
            }
        }
    }

    /// The shipped formulas should pass their own dimensional check.
    func testBuiltInFormulasAreConsistent() {
        let engine = CalculatorEngine(formulas: BuiltInFormulas.all)
        for f in BuiltInFormulas.all {
            let report = UnitChecker(engine: engine).check(f)
            XCTAssertTrue(report.isConsistent, "\(f.name): \(report.warnings.joined(separator: "; "))")
        }
    }
}
