import Foundation

// MARK: - Tables

/// A column of a data table. Cells are kept as typed text so they can hold
/// numbers or small expressions ("1/3", "2.5e-3", "30°"). A column with a
/// `formula` is computed row by row from other columns (`F = m*a`).
struct DataColumn: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var unit: String = ""
    var cells: [String] = []
    /// Expression in other column names; empty for a data column.
    var formula: String = ""

    var isComputed: Bool { !formula.trimmingCharacters(in: .whitespaces).isEmpty }

    init(id: UUID = UUID(), name: String, unit: String = "", cells: [String] = [], formula: String = "") {
        self.id = id; self.name = name; self.unit = unit; self.cells = cells; self.formula = formula
    }

    private enum CodingKeys: String, CodingKey { case id, name, unit, cells, formula }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "x"
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
        cells = try c.decodeIfPresent([String].self, forKey: .cells) ?? []
        formula = try c.decodeIfPresent(String.self, forKey: .formula) ?? ""
    }
}

struct DataTable: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var columns: [DataColumn]
    var rowCount: Int
    var notes: String = ""
    var created = Date()
    var modified = Date()

    init(id: UUID = UUID(), name: String, columns: [DataColumn], rowCount: Int? = nil) {
        self.id = id
        self.name = name
        self.columns = columns
        self.rowCount = rowCount ?? columns.map(\.cells.count).max() ?? 0
        normalize()
    }

    static func blank(name: String = "Untitled Table") -> DataTable {
        DataTable(name: name, columns: [DataColumn(name: "x"), DataColumn(name: "y")], rowCount: 10)
    }

    private enum CodingKeys: String, CodingKey { case id, name, columns, rowCount, notes, created, modified }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Table"
        columns = try c.decodeIfPresent([DataColumn].self, forKey: .columns) ?? []
        rowCount = try c.decodeIfPresent(Int.self, forKey: .rowCount) ?? columns.map(\.cells.count).max() ?? 0
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? Date()
        normalize()
    }

    /// Pads/truncates every column to `rowCount` cells.
    mutating func normalize() {
        rowCount = max(0, rowCount)
        for i in columns.indices {
            if columns[i].cells.count < rowCount {
                columns[i].cells += Array(repeating: "", count: rowCount - columns[i].cells.count)
            } else if columns[i].cells.count > rowCount {
                columns[i].cells.removeLast(columns[i].cells.count - rowCount)
            }
        }
    }

    mutating func addRow() {
        rowCount += 1
        normalize()
    }

    mutating func removeRow(_ index: Int) {
        guard (0..<rowCount).contains(index) else { return }
        for i in columns.indices { columns[i].cells.remove(at: index) }
        rowCount -= 1
    }

    mutating func addColumn(formula: String = "") {
        let used = Set(columns.map(\.name))
        let candidates = ["x", "y", "z", "t", "u", "v", "w", "p", "q", "r", "s"]
        var name = candidates.first { !used.contains($0) } ?? "c"
        if used.contains(name) {
            var n = columns.count + 1
            while used.contains("c\(n)") { n += 1 }
            name = "c\(n)"
        }
        columns.append(DataColumn(name: name, cells: Array(repeating: "", count: rowCount), formula: formula))
    }

    /// Rows whose cells are all empty at the end are dropped (for export/stats).
    var usedRowCount: Int {
        var n = rowCount
        while n > 0, columns.allSatisfy({ $0.isComputed || $0.cells[n - 1].trimmingCharacters(in: .whitespaces).isEmpty }) { n -= 1 }
        return n
    }

    // MARK: Evaluation

    struct Evaluated {
        /// Values per column id; nil for empty or invalid cells.
        var values: [UUID: [Double?]]
        /// Problems per column id (bad formula, cycle).
        var columnErrors: [UUID: String]
        /// Problems per cell, keyed "columnID/row".
        var cellErrors: [String: String]

        func numbers(_ id: UUID) -> [Double] { (values[id] ?? []).compactMap { $0 } }
    }

    /// Evaluates every cell and computed column. Never throws: problems are
    /// reported per column / cell.
    func evaluate(engine: CalculatorEngine) -> Evaluated {
        var result = Evaluated(values: [:], columnErrors: [:], cellErrors: [:])
        let names = Set(columns.map(\.name))

        // Data columns.
        for col in columns where !col.isComputed {
            result.values[col.id] = col.cells.enumerated().map { row, text in
                let t = text.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { return nil }
                if let v = Double(t) { return v }
                do { return try engine.evaluate(expression: t, values: [:]) } catch {
                    result.cellErrors["\(col.id)/\(row)"] = error.localizedDescription
                    return nil
                }
            }
        }

        // Computed columns, in dependency order (a column may use another
        // computed column). Anything left after no progress is a cycle.
        var pending = columns.filter(\.isComputed)
        var compiled: [UUID: Expr] = [:]
        for col in pending {
            do { compiled[col.id] = try engine.compile(col.formula, names: names) } catch {
                result.columnErrors[col.id] = error.localizedDescription
            }
        }
        pending.removeAll { compiled[$0.id] == nil }
        let byName = Dictionary(columns.map { ($0.name, $0.id) }, uniquingKeysWith: { a, _ in a })
        while !pending.isEmpty {
            let ready = pending.filter { col in
                compiled[col.id]!.variables.allSatisfy { n in
                    guard let id = byName[n] else { return true }
                    return id != col.id && result.values[id] != nil
                }
            }
            if ready.isEmpty {
                for col in pending { result.columnErrors[col.id] = "Circular reference between computed columns" }
                break
            }
            for col in ready {
                let expr = compiled[col.id]!
                let used = expr.variables.compactMap { n in byName[n].map { (n, $0) } }
                result.values[col.id] = (0..<rowCount).map { row in
                    var values: [String: Double] = [:]
                    for (n, id) in used {
                        guard let v = result.values[id]?[row] ?? nil else { return nil }
                        values[n] = v
                    }
                    let v = try? engine.evaluate(expr, values: values)
                    return v.flatMap { $0.isFinite ? $0 : nil }
                }
            }
            pending.removeAll { c in ready.contains { $0.id == c.id } }
        }
        return result
    }

    // MARK: CSV

    func csv(engine: CalculatorEngine) -> String {
        let ev = evaluate(engine: engine)
        var lines = [columns.map { CSV.escape($0.unit.isEmpty ? $0.name : "\($0.name) (\($0.unit))") }.joined(separator: ",")]
        for row in 0..<usedRowCount {
            lines.append(columns.map { col -> String in
                if col.isComputed { return ev.values[col.id]?[row].map { NumberFormatting.plain($0) } ?? "" }
                return CSV.escape(col.cells[row])
            }.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Builds a table from CSV text. A first row that isn't numeric becomes
    /// the column names ("time (s)" → name "time", unit "s").
    static func fromCSV(_ text: String, name: String) -> DataTable? {
        let rows = CSV.parse(text).filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let first = rows.first, !first.isEmpty else { return nil }
        let width = rows.map(\.count).max() ?? 0
        let hasHeader = first.contains { cell in
            let t = cell.trimmingCharacters(in: .whitespaces)
            return !t.isEmpty && Double(t) == nil
        }
        let body = hasHeader ? Array(rows.dropFirst()) : rows
        var columns: [DataColumn] = []
        var used = Set<String>()
        for c in 0..<width {
            var (name, unit) = hasHeader && c < first.count ? CSV.splitHeader(first[c]) : ("", "")
            name = CSV.identifier(from: name, fallback: "c\(c + 1)")
            while used.contains(name) { name += "_" }
            used.insert(name)
            let cells = body.map { c < $0.count ? $0[c].trimmingCharacters(in: .whitespaces) : "" }
            columns.append(DataColumn(name: name, unit: unit, cells: cells))
        }
        return DataTable(name: name, columns: columns, rowCount: body.count)
    }
}

enum CSV {
    static func escape(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// RFC 4180-ish parser. Detects `;` or tab separated files too.
    static func parse(_ text: String) -> [[String]] {
        let firstLine = text.prefix { !$0.isNewline }
        let separator: Character
        if firstLine.contains("\t") { separator = "\t" }
        else if !firstLine.contains(","), firstLine.contains(";") { separator = ";" }
        else { separator = "," }

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text)[...]
        while let c = chars.first {
            chars = chars.dropFirst()
            if inQuotes {
                if c == "\"" {
                    if chars.first == "\"" { field.append("\""); chars = chars.dropFirst() } else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == separator {
                row.append(field); field = ""
            } else if c.isNewline {
                if c == "\r", chars.first == "\n" { chars = chars.dropFirst() }
                row.append(field); field = ""
                rows.append(row); row = []
            } else {
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    /// "time (s)" or "time [s]" → ("time", "s").
    static func splitHeader(_ header: String) -> (String, String) {
        let h = header.trimmingCharacters(in: .whitespaces)
        for (open, close) in [("(", ")"), ("[", "]")] {
            if h.hasSuffix(close), let r = h.range(of: open, options: .backwards) {
                let name = h[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
                let unit = h[r.upperBound..<h.index(before: h.endIndex)].trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return (name, unit) }
            }
        }
        return (h, "")
    }

    /// A usable variable name: letters, digits and underscores, starting with a letter.
    static func identifier(from s: String, fallback: String) -> String {
        var out = ""
        for c in s {
            if c.isLetter || c == "_" || (c.isNumber && c.isASCII && !out.isEmpty) { out.append(c) }
            else if c == " " || c == "-" { if !out.isEmpty && out.last != "_" { out.append("_") } }
        }
        while out.hasSuffix("_") { out.removeLast() }
        return out.isEmpty ? fallback : out
    }
}

// MARK: - Statistics

struct Statistics: Equatable {
    var count: Int
    var sum: Double
    var mean: Double
    var median: Double
    var min: Double
    var max: Double
    var q1: Double
    var q3: Double
    /// Sample standard deviation (n − 1).
    var stdDev: Double
    /// Population standard deviation (n).
    var populationStdDev: Double

    var range: Double { max - min }
    var variance: Double { stdDev * stdDev }
    var iqr: Double { q3 - q1 }

    init?(_ values: [Double]) {
        let v = values.filter(\.isFinite).sorted()
        guard !v.isEmpty else { return nil }
        count = v.count
        sum = v.reduce(0, +)
        mean = sum / Double(count)
        min = v[0]
        max = v[count - 1]
        median = Self.quantile(v, 0.5)
        q1 = Self.quantile(v, 0.25)
        q3 = Self.quantile(v, 0.75)
        let m = sum / Double(count)
        let ss = v.reduce(0) { $0 + ($1 - m) * ($1 - m) }
        populationStdDev = (ss / Double(count)).squareRoot()
        stdDev = count > 1 ? (ss / Double(count - 1)).squareRoot() : 0
    }

    /// Linear interpolation between closest ranks (same as Excel QUARTILE.INC).
    static func quantile(_ sorted: [Double], _ p: Double) -> Double {
        guard sorted.count > 1 else { return sorted.first ?? .nan }
        let h = Double(sorted.count - 1) * p
        let lo = Int(h.rounded(.down)), hi = Swift.min(lo + 1, sorted.count - 1)
        return sorted[lo] + (h - Double(lo)) * (sorted[hi] - sorted[lo])
    }
}

/// Pearson correlation of paired values.
func correlation(_ x: [Double], _ y: [Double]) -> Double? {
    let n = Double(x.count)
    guard x.count == y.count, x.count > 1 else { return nil }
    let mx = x.reduce(0, +) / n, my = y.reduce(0, +) / n
    var sxy = 0.0, sxx = 0.0, syy = 0.0
    for (a, b) in zip(x, y) { sxy += (a - mx) * (b - my); sxx += (a - mx) * (a - mx); syy += (b - my) * (b - my) }
    guard sxx > 0, syy > 0 else { return nil }
    return sxy / (sxx * syy).squareRoot()
}

// MARK: - Curve fitting

enum FitModel: String, CaseIterable, Identifiable, Codable {
    case linear = "Linear", quadratic = "Quadratic", exponential = "Exponential", power = "Power"
    var id: String { rawValue }
    var form: String {
        switch self {
        case .linear: return "y = a·x + b"
        case .quadratic: return "y = a·x² + b·x + c"
        case .exponential: return "y = a·e^(b·x)"
        case .power: return "y = a·x^b"
        }
    }
}

struct Fit: Equatable {
    var model: FitModel
    /// linear [a, b]; quadratic [a, b, c]; exponential/power [a, b].
    var coefficients: [Double]
    var r2: Double

    func predict(_ x: Double) -> Double {
        let c = coefficients
        switch model {
        case .linear: return c[0] * x + c[1]
        case .quadratic: return c[0] * x * x + c[1] * x + c[2]
        case .exponential: return c[0] * exp(c[1] * x)
        case .power: return c[0] * pow(x, c[1])
        }
    }

    var equation: String {
        let f = { (v: Double) in NumberFormatting.format(v, digits: 5) }
        func signed(_ v: Double) -> String { v < 0 ? " − \(f(-v))" : " + \(f(v))" }
        let c = coefficients
        switch model {
        case .linear: return "y = \(f(c[0]))·x\(signed(c[1]))"
        case .quadratic: return "y = \(f(c[0]))·x²\(signed(c[1]))·x\(signed(c[2]))"
        case .exponential: return "y = \(f(c[0]))·e^(\(f(c[1]))·x)"
        case .power: return "y = \(f(c[0]))·x^\(f(c[1]))"
        }
    }

    /// Expression usable by the calculator/grapher (`2.5*x + 1`).
    var expression: String {
        let p = { (v: Double) in "(\(NumberFormatting.plain(v)))" }
        let c = coefficients
        switch model {
        case .linear: return "\(p(c[0]))*x + \(p(c[1]))"
        case .quadratic: return "\(p(c[0]))*x^2 + \(p(c[1]))*x + \(p(c[2]))"
        case .exponential: return "\(p(c[0]))*exp(\(p(c[1]))*x)"
        case .power: return "\(p(c[0]))*x^\(p(c[1]))"
        }
    }

    /// Least-squares fit. Returns nil when the data can't support the model
    /// (too few points, non-positive values for log models, singular system).
    static func fit(_ model: FitModel, x: [Double], y: [Double]) -> Fit? {
        let pairs = zip(x, y).filter { $0.0.isFinite && $0.1.isFinite }
        var xs = pairs.map(\.0), ys = pairs.map(\.1)
        let coefficients: [Double]
        switch model {
        case .linear:
            guard let c = polyfit(xs, ys, degree: 1) else { return nil }
            coefficients = [c[1], c[0]]
        case .quadratic:
            guard let c = polyfit(xs, ys, degree: 2) else { return nil }
            coefficients = [c[2], c[1], c[0]]
        case .exponential:
            guard ys.allSatisfy({ $0 > 0 }), let c = polyfit(xs, ys.map { log($0) }, degree: 1) else { return nil }
            coefficients = [exp(c[0]), c[1]]
        case .power:
            guard xs.allSatisfy({ $0 > 0 }), ys.allSatisfy({ $0 > 0 }) else { return nil }
            xs = xs.map { log($0) }
            guard let c = polyfit(xs, ys.map { log($0) }, degree: 1) else { return nil }
            coefficients = [exp(c[0]), c[1]]
            xs = pairs.map(\.0)
        }
        var fit = Fit(model: model, coefficients: coefficients, r2: 0)
        let mean = ys.reduce(0, +) / Double(ys.count)
        let ssTot = ys.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        let ssRes = zip(xs, ys).reduce(0) { $0 + pow($1.1 - fit.predict($1.0), 2) }
        fit.r2 = ssTot > 0 ? 1 - ssRes / ssTot : (ssRes < 1e-12 ? 1 : 0)
        guard fit.coefficients.allSatisfy(\.isFinite) else { return nil }
        return fit
    }

    /// Polynomial least squares; returns coefficients lowest power first.
    static func polyfit(_ x: [Double], _ y: [Double], degree: Int) -> [Double]? {
        let n = degree + 1
        guard x.count == y.count, x.count >= n, Set(x).count >= n else { return nil }
        // Normal equations A·c = b with A[i][j] = Σ x^(i+j), b[i] = Σ y·x^i.
        var a = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        var b = Array(repeating: 0.0, count: n)
        for (xi, yi) in zip(x, y) {
            var powers = [1.0]
            for _ in 0..<(2 * degree) { powers.append(powers.last! * xi) }
            for i in 0..<n {
                b[i] += yi * powers[i]
                for j in 0..<n { a[i][j] += powers[i + j] }
            }
        }
        return solve(a, b)
    }

    /// Gaussian elimination with partial pivoting.
    static func solve(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        var a = matrix, b = rhs
        let n = b.count
        for col in 0..<n {
            guard let pivot = (col..<n).max(by: { abs(a[$0][col]) < abs(a[$1][col]) }), abs(a[pivot][col]) > 1e-12 else { return nil }
            a.swapAt(col, pivot); b.swapAt(col, pivot)
            for r in (col + 1)..<n where r < n {
                let f = a[r][col] / a[col][col]
                for c in col..<n { a[r][c] -= f * a[col][c] }
                b[r] -= f * b[col]
            }
        }
        var x = Array(repeating: 0.0, count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            var s = b[r]
            for c in (r + 1)..<n where c < n { s -= a[r][c] * x[c] }
            x[r] = s / a[r][r]
        }
        return x
    }
}

// MARK: - Function sampling

/// Samples y = f(x) for graphing, splitting the curve at gaps and
/// asymptotes so they aren't joined by vertical lines.
enum FunctionSampler {
    struct Point: Hashable { var x: Double; var y: Double }

    static func sample(_ expr: Expr, engine: CalculatorEngine, xMin: Double, xMax: Double, count: Int = 400) -> [[Point]] {
        guard xMax > xMin, count > 1 else { return [] }
        var segments: [[Point]] = []
        var current: [Point] = []
        var values: [Point] = []
        for i in 0..<count {
            let x = xMin + (xMax - xMin) * Double(i) / Double(count - 1)
            let y = (try? engine.evaluate(expr, values: ["x": x])) ?? .nan
            values.append(Point(x: x, y: y))
        }
        // Typical step size, used to spot jumps (tan x near π/2).
        let finite = values.map(\.y).filter(\.isFinite)
        let spread = finite.isEmpty ? 1 : (Statistics(finite).map { $0.q3 - $0.q1 } ?? 1)
        let jump = max(spread, 1e-9) * 20
        for p in values {
            if !p.y.isFinite {
                if !current.isEmpty { segments.append(current); current = [] }
                continue
            }
            if let last = current.last, abs(p.y - last.y) > jump, (p.y > 0) != (last.y > 0) {
                segments.append(current); current = []
            }
            current.append(p)
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }

    /// A y-range that shows the interesting part of the curves, ignoring
    /// values that shoot off towards asymptotes.
    static func autoRange(_ segments: [[Point]]) -> ClosedRange<Double> {
        let ys = segments.flatMap { $0.map(\.y) }
        guard let s = Statistics(ys) else { return -10...10 }
        let sorted = ys.sorted()
        var lo = Statistics.quantile(sorted, 0.02), hi = Statistics.quantile(sorted, 0.98)
        if s.max - s.min < (hi - lo) * 1.5 { lo = s.min; hi = s.max }
        if hi - lo < 1e-9 { lo -= 1; hi += 1 }
        let pad = (hi - lo) * 0.08
        return (lo - pad)...(hi + pad)
    }
}
