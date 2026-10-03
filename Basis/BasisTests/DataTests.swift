import XCTest
@testable import Basis

final class DataTests: XCTestCase {
    private let engine = CalculatorEngine(angleMode: .radians)

    func testStatistics() throws {
        let s = try XCTUnwrap(Statistics([2, 4, 4, 4, 5, 5, 7, 9]))
        XCTAssertEqual(s.count, 8)
        XCTAssertEqual(s.mean, 5)
        XCTAssertEqual(s.median, 4.5)
        XCTAssertEqual(s.populationStdDev, 2, accuracy: 1e-12)
        XCTAssertEqual(s.stdDev, 2.138089935, accuracy: 1e-9)
        XCTAssertEqual(s.min, 2)
        XCTAssertEqual(s.max, 9)
        XCTAssertEqual(s.q1, 4)
        XCTAssertEqual(s.q3, 5.5)
        XCTAssertNil(Statistics([]))
        XCTAssertNil(Statistics([.nan]))
        XCTAssertEqual(Statistics([3])?.stdDev, 0)
    }

    func testLinearFit() throws {
        let x: [Double] = [0, 1, 2, 3, 4]
        let y = x.map { 2 * $0 + 1 }
        let fit = try XCTUnwrap(Fit.fit(.linear, x: x, y: y))
        XCTAssertEqual(fit.coefficients[0], 2, accuracy: 1e-10)
        XCTAssertEqual(fit.coefficients[1], 1, accuracy: 1e-10)
        XCTAssertEqual(fit.r2, 1, accuracy: 1e-12)
        XCTAssertEqual(fit.equation, "y = 2·x + 1")
        // The expression form can be evaluated by the calculator.
        XCTAssertEqual(try engine.evaluate(expression: fit.expression, values: ["x": 10]), 21, accuracy: 1e-9)
    }

    func testOtherFits() throws {
        let x: [Double] = [1, 2, 3, 4, 5, 6]
        let quad = try XCTUnwrap(Fit.fit(.quadratic, x: x, y: x.map { 3 * $0 * $0 - 2 * $0 + 5 }))
        XCTAssertEqual(quad.coefficients[0], 3, accuracy: 1e-8)
        XCTAssertEqual(quad.coefficients[1], -2, accuracy: 1e-8)
        XCTAssertEqual(quad.coefficients[2], 5, accuracy: 1e-8)
        let expo = try XCTUnwrap(Fit.fit(.exponential, x: x, y: x.map { 2 * exp(0.5 * $0) }))
        XCTAssertEqual(expo.coefficients[0], 2, accuracy: 1e-9)
        XCTAssertEqual(expo.coefficients[1], 0.5, accuracy: 1e-9)
        let power = try XCTUnwrap(Fit.fit(.power, x: x, y: x.map { 4 * pow($0, 1.5) }))
        XCTAssertEqual(power.coefficients[0], 4, accuracy: 1e-9)
        XCTAssertEqual(power.coefficients[1], 1.5, accuracy: 1e-9)
        XCTAssertEqual(power.r2, 1, accuracy: 1e-9)
        // Unsupported data returns nil instead of crashing.
        XCTAssertNil(Fit.fit(.exponential, x: [1, 2], y: [-1, 2]))
        XCTAssertNil(Fit.fit(.linear, x: [1], y: [1]))
        XCTAssertNil(Fit.fit(.linear, x: [2, 2, 2], y: [1, 2, 3]))
        XCTAssertNil(Fit.fit(.quadratic, x: [1, 2], y: [1, 2]))
    }

    func testCorrelation() {
        XCTAssertEqual(correlation([1, 2, 3], [2, 4, 6]) ?? 0, 1, accuracy: 1e-12)
        XCTAssertEqual(correlation([1, 2, 3], [6, 4, 2]) ?? 0, -1, accuracy: 1e-12)
        XCTAssertNil(correlation([1, 1, 1], [1, 2, 3]))
    }

    func testComputedColumns() {
        var t = DataTable(name: "Motion", columns: [
            DataColumn(name: "mass", unit: "kg", cells: ["1", "2", "", "1/2"]),
            DataColumn(name: "acc", unit: "m/s²", cells: ["10", "5", "3", "bad("]),
        ])
        t.columns.append(DataColumn(name: "F", unit: "N", formula: "mass*acc"))
        t.columns.append(DataColumn(name: "F2", formula: "F*2"))   // depends on a computed column
        t.normalize()
        let ev = t.evaluate(engine: engine)
        XCTAssertEqual(ev.values[t.columns[2].id]!, [10, 10, nil, nil])
        XCTAssertEqual(ev.values[t.columns[3].id]!, [20, 20, nil, nil])
        XCTAssertEqual(ev.values[t.columns[0].id]![3], 0.5)
        XCTAssertNotNil(ev.cellErrors["\(t.columns[1].id)/3"])
        XCTAssertTrue(ev.columnErrors.isEmpty)
    }

    func testComputedColumnCycleAndErrors() {
        var t = DataTable(name: "Loop", columns: [DataColumn(name: "x", cells: ["1", "2"])])
        t.columns.append(DataColumn(name: "a", formula: "b + 1"))
        t.columns.append(DataColumn(name: "b", formula: "a + 1"))
        t.columns.append(DataColumn(name: "c", formula: "x +* 2"))
        t.normalize()
        let ev = t.evaluate(engine: engine)
        XCTAssertNotNil(ev.columnErrors[t.columns[1].id])
        XCTAssertNotNil(ev.columnErrors[t.columns[2].id])
        XCTAssertNotNil(ev.columnErrors[t.columns[3].id])
    }

    func testMultiLetterColumnNamesStayWhole() {
        var t = DataTable(name: "T", columns: [DataColumn(name: "vel", cells: ["3"]), DataColumn(name: "tim", cells: ["2"])])
        t.columns.append(DataColumn(name: "dist", formula: "vel*tim"))
        t.normalize()
        XCTAssertEqual(t.evaluate(engine: engine).values[t.columns[2].id]!, [6])
    }

    func testCSVRoundTrip() throws {
        let csv = "time (s),\"distance, total [m]\"\n0,0\n1,4.9\n2,19.6\n"
        let t = try XCTUnwrap(DataTable.fromCSV(csv, name: "Drop"))
        XCTAssertEqual(t.columns.map(\.name), ["time", "distance_total"])
        XCTAssertEqual(t.columns.map(\.unit), ["s", "m"])
        XCTAssertEqual(t.rowCount, 3)
        XCTAssertEqual(t.columns[1].cells, ["0", "4.9", "19.6"])

        let out = t.csv(engine: engine)
        XCTAssertTrue(out.hasPrefix("time (s),distance_total (m)\n0,0\n"), out)
        let again = try XCTUnwrap(DataTable.fromCSV(out, name: "x"))
        XCTAssertEqual(again.columns.map(\.cells), t.columns.map(\.cells))
    }

    func testCSVVariants() throws {
        let semicolon = try XCTUnwrap(DataTable.fromCSV("a;b\r\n1;2\r\n3;4", name: "s"))
        XCTAssertEqual(semicolon.columns.map(\.name), ["a", "b"])
        XCTAssertEqual(semicolon.columns[1].cells, ["2", "4"])
        let noHeader = try XCTUnwrap(DataTable.fromCSV("1\t2\n3\t4\n", name: "n"))
        XCTAssertEqual(noHeader.columns.map(\.name), ["c1", "c2"])
        XCTAssertEqual(noHeader.rowCount, 2)
        XCTAssertNil(DataTable.fromCSV("", name: "e"))
    }

    func testTableEditing() {
        var t = DataTable.blank()
        XCTAssertEqual(t.rowCount, 10)
        t.columns[0].cells[0] = "1"
        t.addColumn()
        XCTAssertEqual(t.columns.map(\.name), ["x", "y", "z"])
        XCTAssertEqual(t.columns[2].cells.count, 10)
        t.removeRow(0)
        XCTAssertEqual(t.rowCount, 9)
        XCTAssertEqual(t.usedRowCount, 0)
        XCTAssertEqual(ColumnEditorView.rename("x", to: "time", in: "x^2 + max(x, xx)"), "time^2 + max(time, xx)")
    }

    func testTableDecodingIsTolerant() throws {
        let json = #"{"name":"Old","columns":[{"name":"x","cells":["1","2","3"]}]}"#
        let t = try JSONDecoder().decode(DataTable.self, from: Data(json.utf8))
        XCTAssertEqual(t.rowCount, 3)
        XCTAssertEqual(t.columns[0].formula, "")
    }

    func testFunctionSamplingSplitsAsymptotes() throws {
        let expr = try engine.compile("tan(x)", names: ["x"])
        let segments = FunctionSampler.sample(expr, engine: engine, xMin: -3, xMax: 3, count: 600)
        XCTAssertGreaterThanOrEqual(segments.count, 3)   // pieces between −π/2 and π/2
        let range = FunctionSampler.autoRange(segments)
        XCTAssertLessThan(range.upperBound, 1000)

        let sqrtExpr = try engine.compile("sqrt(x)", names: ["x"])
        let half = FunctionSampler.sample(sqrtExpr, engine: engine, xMin: -4, xMax: 4)
        XCTAssertEqual(half.count, 1)
        XCTAssertTrue(half[0].allSatisfy { $0.x >= 0 })
    }

    @MainActor
    func testTablesPersist() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = CalculatorStore(directory: dir)
        var t = DataTable.blank(name: "Lab 1")
        t.columns[0].cells[0] = "42"
        store.save(t)
        store.flush()
        let reloaded = CalculatorStore(directory: dir)
        XCTAssertEqual(reloaded.tables.first?.name, "Lab 1")
        XCTAssertEqual(reloaded.tables.first?.columns[0].cells[0], "42")
    }
}
