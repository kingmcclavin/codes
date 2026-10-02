import XCTest
@testable import InkPad

final class SolverTests: XCTestCase {
    private let engine = CalculatorEngine(angleMode: .radians, formulas: BuiltInFormulas.all)

    func testPolynomialRoots() {
        let r = Solver.solve("x^2 = 2", engine: engine, lo: -10, hi: 10)
        XCTAssertNil(r.error)
        XCTAssertEqual(r.roots.count, 2)
        XCTAssertEqual(r.roots[0], -2.0.squareRoot(), accuracy: 1e-10)
        XCTAssertEqual(r.roots[1], 2.0.squareRoot(), accuracy: 1e-10)

        let cubic = Solver.solve("x^3 - 6x^2 + 11x - 6", engine: engine, lo: -10, hi: 10)
        XCTAssertEqual(cubic.roots.count, 3)
        for (got, want) in zip(cubic.roots, [1.0, 2, 3]) { XCTAssertEqual(got, want, accuracy: 1e-9) }
    }

    func testTranscendentalAndTouchingRoots() {
        let r = Solver.solve("cos(x) = x", engine: engine, lo: -5, hi: 5)
        XCTAssertEqual(r.roots.count, 1)
        XCTAssertEqual(r.roots[0], 0.7390851332, accuracy: 1e-9)

        let touching = Solver.solve("(x - 1.3)^2", engine: engine, lo: -5, hi: 5)
        XCTAssertEqual(touching.roots.count, 1)
        XCTAssertEqual(touching.roots.first ?? 0, 1.3, accuracy: 1e-6)
    }

    func testPolesAreNotRoots() {
        let r = Solver.solve("tan(x) = 0", engine: engine, lo: -2, hi: 2)
        XCTAssertEqual(r.roots.count, 1)   // x = 0 only, not ±π/2
        XCTAssertEqual(r.roots.first ?? 1, 0, accuracy: 1e-9)
        XCTAssertTrue(Solver.solve("1/x", engine: engine, lo: -3, hi: 3).roots.isEmpty)
    }

    func testOtherUnknownAndErrors() {
        let r = Solver.solve("2t + 1 = 7", engine: engine, lo: -10, hi: 10)
        XCTAssertEqual(r.variable, "t")
        XCTAssertEqual(r.roots.first ?? 0, 3, accuracy: 1e-10)
        XCTAssertNotNil(Solver.solve("a + b = 1", engine: engine, lo: 0, hi: 1).error)
        XCTAssertNotNil(Solver.solve("x^2 = -1", engine: engine, lo: -10, hi: 10).error)
        XCTAssertNotNil(Solver.solve("x + (", engine: engine, lo: 0, hi: 1).error)
        XCTAssertNotNil(Solver.solve("x = 1 = 2", engine: engine, lo: 0, hi: 1).error)
    }

    func testSolveFormulaBackwards() throws {
        let ke = try XCTUnwrap(BuiltInFormulas.all.first { $0.name == "Kinetic Energy" })
        // KE = ½ m v² = 100 J with m = 2 kg → v = ±10 m/s
        let v = Solver.solve(ke, engine: engine, unknown: "v", knowns: ["m": 2], output: "KE", target: 100)
        XCTAssertEqual(v.count, 2)
        XCTAssertEqual(v.last ?? 0, 10, accuracy: 1e-8)
        let m = Solver.solve(ke, engine: engine, unknown: "m", knowns: ["v": 3], output: "KE", target: 9)
        XCTAssertEqual(m.first ?? 0, 2, accuracy: 1e-9)

        let ohm = try XCTUnwrap(BuiltInFormulas.all.first { $0.name == "Ohm's Law" })
        let r = Solver.solve(ohm, engine: engine, unknown: "R", knowns: ["I": 0.002], output: "V", target: 5)
        XCTAssertEqual(r.first ?? 0, 2500, accuracy: 1e-6)
    }
}

final class MatrixTests: XCTestCase {
    func testArithmetic() throws {
        let a = Matrix([[1, 2], [3, 4]]), b = Matrix([[5, 6], [7, 8]])
        XCTAssertEqual(try a * b, Matrix([[19, 22], [43, 50]]))
        XCTAssertEqual(try a + b, Matrix([[6, 8], [10, 12]]))
        XCTAssertEqual(a.transposed, Matrix([[1, 3], [2, 4]]))
        XCTAssertThrowsError(try a * Matrix([[1, 2, 3]]))
    }

    func testDeterminantInverseRank() throws {
        let a = Matrix([[2, -1, 0], [-1, 2, -1], [0, -1, 2]])
        XCTAssertEqual(try a.determinant(), 4, accuracy: 1e-12)
        let product = try a * a.inverse()
        for r in 0..<3 { for c in 0..<3 { XCTAssertEqual(product[r, c], r == c ? 1 : 0, accuracy: 1e-12) } }
        XCTAssertEqual(a.rank, 3)

        let singular = Matrix([[1, 2], [2, 4]])
        XCTAssertEqual(try singular.determinant(), 0)
        XCTAssertThrowsError(try singular.inverse())
        XCTAssertEqual(singular.rank, 1)
        XCTAssertThrowsError(try Matrix([[1, 2, 3]]).determinant())
    }

    func testLinearSystem() throws {
        // x + y + z = 6, 2y + 5z = −4, 2x + 5y − z = 27 → (5, 3, −2)
        let a = Matrix([[1, 1, 1], [0, 2, 5], [2, 5, -1]])
        let x = try a.solve(Matrix([[6], [-4], [27]]))
        XCTAssertEqual(x[0, 0], 5, accuracy: 1e-10)
        XCTAssertEqual(x[1, 0], 3, accuracy: 1e-10)
        XCTAssertEqual(x[2, 0], -2, accuracy: 1e-10)
    }

    func testVectors() {
        let a = Vector3(x: 1, y: 0, z: 0), b = Vector3(x: 0, y: 1, z: 0)
        XCTAssertEqual(a.cross(b), Vector3(x: 0, y: 0, z: 1))
        XCTAssertEqual(a.dot(b), 0)
        XCTAssertEqual(a.angle(to: b) ?? 0, .pi / 2, accuracy: 1e-12)
        XCTAssertEqual(Vector3(x: 3, y: 4, z: 0).magnitude, 5)
        XCTAssertEqual(Vector3(x: 2, y: 2, z: 0).projection(onto: a), Vector3(x: 2, y: 0, z: 0))
        XCTAssertNil(Vector3(x: 0, y: 0, z: 0).unit)
    }

    func testNumberBases() {
        XCTAssertEqual(NumberBase.parse("ff", base: .hex), 255)
        XCTAssertEqual(NumberBase.parse("0b1010", base: .decimal), 10)
        XCTAssertEqual(NumberBase.parse("1_000", base: .decimal), 1000)
        XCTAssertNil(NumberBase.parse("12", base: .binary))
        XCTAssertNil(NumberBase.parse("", base: .decimal))
        XCTAssertEqual(NumberBase.hex.format(255, bits: 8), "FF")
        XCTAssertEqual(NumberBase.binary.format(10, bits: 8), "1010")
        XCTAssertEqual(NumberBase.binary.format(-1, bits: 8), "1111 1111")
        XCTAssertEqual(NumberBase.hex.format(-2, bits: 16), "FFFE")
        XCTAssertEqual(NumberBase.octal.format(8, bits: 8), "10")
        XCTAssertEqual(NumberBase.decimal.format(-42), "-42")
        XCTAssertEqual(NumberBase.bitsNeeded(200), 8)
        XCTAssertEqual(NumberBase.bitsNeeded(-200), 16)
    }
}

final class StructuralTests: XCTestCase {
    func testRectangleAndIBeam() throws {
        let r = try SectionProperties.compute(.rectangle, ["b": 100, "h": 200])
        XCTAssertEqual(r.area, 20_000)
        XCTAssertEqual(r.centroidY, 100)
        XCTAssertEqual(r.ix, 100 * pow(200, 3) / 12, accuracy: 1e-6)
        XCTAssertEqual(r.sx, r.ix / 100, accuracy: 1e-9)

        let i = try SectionProperties.compute(.iBeam, ["b": 100, "h": 200, "tf": 10, "tw": 6])
        XCTAssertEqual(i.area, 2 * 100 * 10 + 6 * 180, accuracy: 1e-9)
        XCTAssertEqual(i.centroidY, 100, accuracy: 1e-9)
        let expected = (100 * pow(200, 3) - 94 * pow(180, 3)) / 12
        XCTAssertEqual(i.ix, expected, accuracy: 1e-6)
        XCTAssertEqual(i.iy, 2 * 10 * pow(100, 3) / 12 + 180 * pow(6, 3) / 12, accuracy: 1e-6)
    }

    func testHollowShapesAndTee() throws {
        let tube = try SectionProperties.compute(.tube, ["D": 60, "t": 5])
        XCTAssertEqual(tube.ix, .pi * (pow(60, 4) - pow(50, 4)) / 64, accuracy: 1e-6)
        let box = try SectionProperties.compute(.hollowRectangle, ["b": 100, "h": 200, "t": 10])
        XCTAssertEqual(box.ix, (100 * pow(200, 3) - 80 * pow(180, 3)) / 12, accuracy: 1e-6)
        XCTAssertEqual(box.iy, (200 * pow(100, 3) - 180 * pow(80, 3)) / 12, accuracy: 1e-6)
        let tee = try SectionProperties.compute(.tee, ["b": 100, "h": 100, "tf": 20, "tw": 20])
        // Web 20×80 (centroid 40), flange 100×20 (centroid 90): ȳ = (1600·40 + 2000·90) / 3600
        XCTAssertEqual(tee.centroidY, (1600 * 40 + 2000 * 90) / 3600.0, accuracy: 1e-9)
        XCTAssertThrowsError(try SectionProperties.compute(.tube, ["D": 10, "t": 6]))
        XCTAssertThrowsError(try SectionProperties.compute(.rectangle, ["b": 10]))
    }

    private let ei = 200e9 * 8.36e-5   // E = 200 GPa, I = 8.36e7 mm⁴

    func testSimplySupportedPointLoad() throws {
        let p = 10_000.0, l = 6.0
        let r = try Beam(support: .simplySupported, length: l, loads: [.point(p: p, a: l / 2)], ei: ei).analyze()
        XCTAssertEqual(r.reactionLeft, p / 2, accuracy: 1e-9)
        XCTAssertEqual(r.reactionRight, p / 2, accuracy: 1e-9)
        XCTAssertEqual(r.maxMoment.value, p * l / 4, accuracy: 1e-6)
        XCTAssertEqual(r.maxMoment.x, l / 2, accuracy: 1e-9)
        XCTAssertEqual(r.maxDeflection.value, p * pow(l, 3) / (48 * ei), accuracy: p * pow(l, 3) / (48 * ei) * 1e-3)
        XCTAssertEqual(r.maxShear, p / 2, accuracy: 1e-9)
        XCTAssertEqual(r.moment.first ?? 1, 0, accuracy: 1e-9)
        XCTAssertEqual(r.moment.last ?? 1, 0, accuracy: 1e-6)
    }

    func testSimplySupportedUniformLoad() throws {
        let w = 5_000.0, l = 8.0
        let r = try Beam(support: .simplySupported, length: l, loads: [.distributed(w: w, a: 0, b: l)], ei: ei).analyze()
        XCTAssertEqual(r.reactionLeft, w * l / 2, accuracy: 1e-6)
        XCTAssertEqual(r.maxMoment.value, w * l * l / 8, accuracy: 1e-3)
        let expected = 5 * w * pow(l, 4) / (384 * ei)
        XCTAssertEqual(r.maxDeflection.value, expected, accuracy: expected * 1e-3)
    }

    func testCantilever() throws {
        let p = 2_000.0, l = 3.0
        let r = try Beam(support: .cantilever, length: l, loads: [.point(p: p, a: l)], ei: ei).analyze()
        XCTAssertEqual(r.reactionLeft, p, accuracy: 1e-9)
        XCTAssertEqual(r.fixedMoment, -p * l, accuracy: 1e-9)
        XCTAssertEqual(r.maxMoment.value, -p * l, accuracy: 1e-9)
        XCTAssertEqual(r.moment.last ?? 1, 0, accuracy: 1e-9)
        let expected = p * pow(l, 3) / (3 * ei)
        XCTAssertEqual(r.maxDeflection.value, expected, accuracy: expected * 1e-3)
        XCTAssertEqual(r.maxDeflection.x, l, accuracy: 1e-9)
    }

    func testAppliedMomentEquilibrium() throws {
        // Clockwise 12 kN·m at midspan of a 4 m simply supported beam.
        let r = try Beam(support: .simplySupported, length: 4, loads: [.moment(m: 12_000, a: 2)]).analyze()
        XCTAssertEqual(r.reactionRight, 3_000, accuracy: 1e-9)
        XCTAssertEqual(r.reactionLeft, -3_000, accuracy: 1e-9)
        XCTAssertEqual(r.moment.last ?? 1, 0, accuracy: 1e-6)
        XCTAssertTrue(r.deflection.isEmpty)   // no EI given
    }

    func testInvalidBeams() {
        XCTAssertThrowsError(try Beam(support: .cantilever, length: 0, loads: []).analyze())
        XCTAssertThrowsError(try Beam(support: .cantilever, length: 2, loads: [.point(p: 1, a: 3)]).analyze())
    }
}
