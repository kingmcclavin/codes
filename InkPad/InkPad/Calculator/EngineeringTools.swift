import Foundation

// MARK: - Root finding

/// Numeric equation solving: finds every root of f in a set of sample
/// points (sign changes refined by bisection, touching roots by a
/// golden-section search on |f|). Never throws; bad points are skipped.
enum Solver {
    /// Samples that cover many orders of magnitude, for unknowns of
    /// unknown scale (0, ±1e-6 … ±1e9).
    static let wideSamples: [Double] = {
        var s: [Double] = [0]
        for k in -6...9 {
            for m in [1.0, 1.5, 2, 3, 4, 5, 6, 7, 8, 9] {
                let v = m * pow(10, Double(k))
                s.append(v); s.append(-v)
            }
        }
        return s.sorted()
    }()

    static func uniformSamples(_ lo: Double, _ hi: Double, count: Int = 2000) -> [Double] {
        guard hi > lo, count > 1 else { return [lo] }
        return (0..<count).map { lo + (hi - lo) * Double($0) / Double(count - 1) }
    }

    static func roots(of f: (Double) -> Double?, samples: [Double], maxRoots: Int = 20) -> [Double] {
        let values: [(x: Double, y: Double)] = samples.compactMap { x in
            guard let y = f(x), y.isFinite else { return nil }
            return (x, y)
        }
        guard !values.isEmpty else { return [] }
        let scale = max(values.map { abs($0.y) }.max() ?? 1, 1e-300)
        var found: [Double] = []

        func accept(_ x: Double) {
            guard let y = f(x), y.isFinite else { return }
            // Reject sign changes across poles (|f| large at the "root").
            let near = values.min { abs($0.x - x) < abs($1.x - x) }.map { abs($0.y) } ?? scale
            guard abs(y) <= max(1e-9 * scale, near * 1e-6, 1e-12) || abs(y) < 1e-10 else { return }
            let tol = max(1e-9, abs(x) * 1e-7)
            if !found.contains(where: { abs($0 - x) <= tol }) { found.append(x) }
        }

        for i in values.indices {
            let p = values[i]
            if p.y == 0 { accept(p.x); continue }
            guard i + 1 < values.count else { continue }
            let q = values[i + 1]
            if q.y != 0, (p.y < 0) != (q.y < 0) {
                if let r = bisect(f, p.x, q.x, p.y) { accept(r) }
            } else if i > 0 {
                // Touching root: |f| has a local minimum close to zero.
                let o = values[i - 1]
                if abs(p.y) < abs(o.y), abs(p.y) < abs(q.y), (o.y > 0) == (p.y > 0), (q.y > 0) == (p.y > 0) {
                    let x = goldenMin({ f($0).map(abs) ?? .infinity }, o.x, q.x)
                    if let y = f(x), abs(y) < 1e-9 * max(scale, 1) { accept(x) }
                }
            }
            if found.count >= maxRoots { break }
        }
        return found.sorted().map(clean)
    }

    /// Rounds values like 2.0000000000004 to 2 for display.
    static func clean(_ x: Double) -> Double {
        let r = (x * 1e9).rounded() / 1e9
        return abs(r - x) < 1e-11 * max(1, abs(x)) ? r : x
    }

    private static func bisect(_ f: (Double) -> Double?, _ a0: Double, _ b0: Double, _ fa0: Double) -> Double? {
        var a = a0, b = b0, fa = fa0
        for _ in 0..<200 {
            let m = (a + b) / 2
            guard let fm = f(m), fm.isFinite else { return nil }
            if fm == 0 || (b - a) / 2 < 1e-15 * max(1, abs(m)) { return m }
            if (fm < 0) == (fa < 0) { a = m; fa = fm } else { b = m }
        }
        return (a + b) / 2
    }

    private static func goldenMin(_ g: (Double) -> Double, _ a0: Double, _ b0: Double) -> Double {
        let phi = (5.0.squareRoot() - 1) / 2
        var a = a0, b = b0
        var c = b - phi * (b - a), d = a + phi * (b - a)
        for _ in 0..<200 {
            if g(c) < g(d) { b = d } else { a = c }
            c = b - phi * (b - a); d = a + phi * (b - a)
            if abs(b - a) < 1e-14 * max(1, abs(a)) { break }
        }
        return (a + b) / 2
    }

    // MARK: Equations

    struct EquationResult {
        var variable: String
        var roots: [Double]
        var error: String?
    }

    /// Solves an equation such as `x^3 - 2x = 5` (or an expression = 0) for
    /// its single unknown within [lo, hi].
    static func solve(_ text: String, engine: CalculatorEngine, lo: Double, hi: Double, variable: String? = nil) -> EquationResult {
        let parts = text.split(separator: "=", omittingEmptySubsequences: false).map(String.init)
        guard parts.count <= 2, !(parts.first ?? "").trimmingCharacters(in: .whitespaces).isEmpty else {
            return EquationResult(variable: "x", roots: [], error: "Write one equation, e.g. x^2 = 2")
        }
        let lhsText = parts[0], rhsText = parts.count == 2 ? parts[1] : "0"
        let names: Set<String> = variable.map { [$0] } ?? ["x"]
        do {
            let lhs = try engine.compile(lhsText, names: names)
            let rhs = try engine.compile(rhsText.trimmingCharacters(in: .whitespaces).isEmpty ? "0" : rhsText, names: names)
            // The unknown: the requested name, else x, else the only free name.
            let free = Set(lhs.variables + rhs.variables).filter {
                !Constants.isConstant($0) && $0 != "ans" && (try? engine.value(ofVariable: $0)) == nil
            }
            let v = variable ?? (free.contains("x") || free.isEmpty ? "x" : (free.count == 1 ? free.first! : ""))
            guard !v.isEmpty else {
                return EquationResult(variable: "x", roots: [], error: "More than one unknown: \(free.sorted().joined(separator: ", "))")
            }
            if free.subtracting([v]).count > 0 {
                return EquationResult(variable: v, roots: [], error: "Unknown names: \(free.subtracting([v]).sorted().joined(separator: ", "))")
            }
            let f: (Double) -> Double? = { x in
                guard let a = try? engine.evaluate(lhs, values: [v: x]), let b = try? engine.evaluate(rhs, values: [v: x]) else { return nil }
                return a - b
            }
            let roots = Solver.roots(of: f, samples: uniformSamples(lo, hi))
            return EquationResult(variable: v, roots: roots, error: roots.isEmpty ? "No solution between \(NumberFormatting.format(lo)) and \(NumberFormatting.format(hi))" : nil)
        } catch {
            return EquationResult(variable: variable ?? "x", roots: [], error: error.localizedDescription)
        }
    }

    /// Solves a formula backwards: the value of input `unknown` that makes
    /// `output` equal `target`, given the other inputs.
    static func solve(_ formula: Formula, engine: CalculatorEngine, unknown: String, knowns: [String: Double],
                      output: String, target: Double) -> [Double] {
        let f: (Double) -> Double? = { u in
            var inputs = knowns
            inputs[unknown] = u
            let result = engine.evaluate(formula, inputs: inputs)
            guard let v = result.outputs.first(where: { $0.name == output })?.value else { return nil }
            return v - target
        }
        return roots(of: f, samples: wideSamples)
    }
}

// MARK: - Matrices

struct Matrix: Equatable {
    var rows: Int
    var cols: Int
    var values: [Double]

    init(rows: Int, cols: Int, values: [Double]? = nil) {
        self.rows = rows
        self.cols = cols
        self.values = values ?? Array(repeating: 0, count: rows * cols)
    }

    init(_ rows: [[Double]]) {
        self.init(rows: rows.count, cols: rows.first?.count ?? 0, values: rows.flatMap { $0 })
    }

    static func identity(_ n: Int) -> Matrix {
        var m = Matrix(rows: n, cols: n)
        for i in 0..<n { m[i, i] = 1 }
        return m
    }

    subscript(r: Int, c: Int) -> Double {
        get { values[r * cols + c] }
        set { values[r * cols + c] = newValue }
    }

    var isSquare: Bool { rows == cols }

    var transposed: Matrix {
        var t = Matrix(rows: cols, cols: rows)
        for r in 0..<rows { for c in 0..<cols { t[c, r] = self[r, c] } }
        return t
    }

    enum MatrixError: LocalizedError {
        case dimensions(String), singular, notSquare
        var errorDescription: String? {
            switch self {
            case let .dimensions(s): return "Sizes don't match: \(s)"
            case .singular: return "The matrix is singular (no inverse)"
            case .notSquare: return "The matrix must be square"
            }
        }
    }

    static func + (a: Matrix, b: Matrix) throws -> Matrix {
        guard a.rows == b.rows, a.cols == b.cols else { throw MatrixError.dimensions("\(a.rows)×\(a.cols) + \(b.rows)×\(b.cols)") }
        return Matrix(rows: a.rows, cols: a.cols, values: zip(a.values, b.values).map(+))
    }

    static func - (a: Matrix, b: Matrix) throws -> Matrix {
        guard a.rows == b.rows, a.cols == b.cols else { throw MatrixError.dimensions("\(a.rows)×\(a.cols) − \(b.rows)×\(b.cols)") }
        return Matrix(rows: a.rows, cols: a.cols, values: zip(a.values, b.values).map(-))
    }

    static func * (a: Matrix, b: Matrix) throws -> Matrix {
        guard a.cols == b.rows else { throw MatrixError.dimensions("\(a.rows)×\(a.cols) · \(b.rows)×\(b.cols)") }
        var m = Matrix(rows: a.rows, cols: b.cols)
        for i in 0..<a.rows { for j in 0..<b.cols {
            var s = 0.0
            for k in 0..<a.cols { s += a[i, k] * b[k, j] }
            m[i, j] = s
        } }
        return m
    }

    func scaled(_ k: Double) -> Matrix { Matrix(rows: rows, cols: cols, values: values.map { $0 * k }) }

    private var tolerance: Double { 1e-12 * max(1, values.map(abs).max() ?? 1) }

    func determinant() throws -> Double {
        guard isSquare else { throw MatrixError.notSquare }
        var a = self, det = 1.0
        for c in 0..<cols {
            guard let p = (c..<rows).max(by: { abs(a[$0, c]) < abs(a[$1, c]) }), abs(a[p, c]) > tolerance else { return 0 }
            if p != c { a.swapRows(p, c); det = -det }
            det *= a[c, c]
            for r in (c + 1)..<rows where r < rows {
                let f = a[r, c] / a[c, c]
                for k in c..<cols { a[r, k] -= f * a[c, k] }
            }
        }
        return det
    }

    func inverse() throws -> Matrix {
        guard isSquare else { throw MatrixError.notSquare }
        let n = rows
        var a = self, inv = Matrix.identity(n)
        for c in 0..<n {
            guard let p = (c..<n).max(by: { abs(a[$0, c]) < abs(a[$1, c]) }), abs(a[p, c]) > tolerance else { throw MatrixError.singular }
            a.swapRows(p, c); inv.swapRows(p, c)
            let d = a[c, c]
            for k in 0..<n { a[c, k] /= d; inv[c, k] /= d }
            for r in 0..<n where r != c {
                let f = a[r, c]
                if f == 0 { continue }
                for k in 0..<n { a[r, k] -= f * a[c, k]; inv[r, k] -= f * inv[c, k] }
            }
        }
        return inv
    }

    var rank: Int {
        var a = self, rank = 0
        for c in 0..<cols where rank < rows {
            guard let p = (rank..<rows).max(by: { abs(a[$0, c]) < abs(a[$1, c]) }), abs(a[p, c]) > tolerance else { continue }
            a.swapRows(p, rank)
            for r in (rank + 1)..<rows where r < rows {
                let f = a[r, c] / a[rank, c]
                for k in c..<cols { a[r, k] -= f * a[rank, k] }
            }
            rank += 1
        }
        return rank
    }

    /// Solves A·x = b (b is a column vector or several columns).
    func solve(_ b: Matrix) throws -> Matrix {
        guard b.rows == rows else { throw MatrixError.dimensions("A is \(rows)×\(cols), b has \(b.rows) rows") }
        return try inverse() * b
    }

    mutating func swapRows(_ i: Int, _ j: Int) {
        guard i != j else { return }
        for c in 0..<cols { values.swapAt(i * cols + c, j * cols + c) }
    }

    mutating func resize(rows r: Int, cols c: Int) {
        var m = Matrix(rows: r, cols: c)
        for i in 0..<min(r, rows) { for j in 0..<min(c, cols) { m[i, j] = self[i, j] } }
        self = m
    }
}

// MARK: - Vectors

struct Vector3: Equatable {
    var x: Double, y: Double, z: Double

    static func + (a: Vector3, b: Vector3) -> Vector3 { Vector3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
    static func - (a: Vector3, b: Vector3) -> Vector3 { Vector3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
    static func * (a: Vector3, k: Double) -> Vector3 { Vector3(x: a.x * k, y: a.y * k, z: a.z * k) }

    var magnitude: Double { (x * x + y * y + z * z).squareRoot() }
    var unit: Vector3? { magnitude > 0 ? self * (1 / magnitude) : nil }
    func dot(_ b: Vector3) -> Double { x * b.x + y * b.y + z * b.z }
    func cross(_ b: Vector3) -> Vector3 { Vector3(x: y * b.z - z * b.y, y: z * b.x - x * b.z, z: x * b.y - y * b.x) }

    /// Angle between vectors in radians.
    func angle(to b: Vector3) -> Double? {
        let m = magnitude * b.magnitude
        guard m > 0 else { return nil }
        return acos(max(-1, min(1, dot(b) / m)))
    }

    /// Projection of self onto b.
    func projection(onto b: Vector3) -> Vector3? {
        let bb = b.dot(b)
        guard bb > 0 else { return nil }
        return b * (dot(b) / bb)
    }

    var text: String {
        "⟨\(NumberFormatting.format(x, digits: 8)), \(NumberFormatting.format(y, digits: 8)), \(NumberFormatting.format(z, digits: 8))⟩"
    }
}

// MARK: - Number bases

enum NumberBase: Int, CaseIterable, Identifiable {
    case binary = 2, octal = 8, decimal = 10, hex = 16
    var id: Int { rawValue }
    var name: String {
        switch self {
        case .binary: return "Binary"
        case .octal: return "Octal"
        case .decimal: return "Decimal"
        case .hex: return "Hexadecimal"
        }
    }

    /// Parses text in this base. Accepts 0b/0o/0x prefixes, `_` and spaces,
    /// and a leading minus sign.
    static func parse(_ text: String, base: NumberBase) -> Int64? {
        var t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "")
        var negative = false
        if t.hasPrefix("-") { negative = true; t.removeFirst() }
        var b = base
        let lower = t.lowercased()
        if lower.hasPrefix("0x") { b = .hex; t.removeFirst(2) }
        else if lower.hasPrefix("0b") { b = .binary; t.removeFirst(2) }
        else if lower.hasPrefix("0o") { b = .octal; t.removeFirst(2) }
        guard !t.isEmpty, let magnitude = UInt64(t, radix: b.rawValue) else { return nil }
        if negative {
            guard magnitude <= UInt64(Int64.max) + 1 else { return nil }
            return magnitude == UInt64(Int64.max) + 1 ? Int64.min : -Int64(magnitude)
        }
        guard magnitude <= UInt64(Int64.max) else { return nil }
        return Int64(magnitude)
    }

    /// Formats a value; negative numbers use two's complement at `bits`
    /// for binary/octal/hex.
    func format(_ v: Int64, bits: Int = 32, grouped: Bool = true) -> String {
        if self == .decimal { return String(v) }
        let mask: UInt64 = bits >= 64 ? .max : (1 << UInt64(bits)) - 1
        let raw = UInt64(bitPattern: v) & mask
        var s = String(raw, radix: rawValue).uppercased()
        if self == .binary, v < 0 || grouped {
            let width = v < 0 ? bits : ((s.count + 3) / 4) * 4
            s = String(repeating: "0", count: max(0, width - s.count)) + s
        }
        guard grouped else { return s }
        let group = self == .binary ? 4 : (self == .hex ? 4 : 3)
        var out = ""
        for (i, ch) in s.enumerated() {
            if i > 0, (s.count - i) % group == 0 { out.append(" ") }
            out.append(ch)
        }
        return out
    }

    /// Smallest standard width (8/16/32/64) that holds the value.
    static func bitsNeeded(_ v: Int64) -> Int {
        for bits in [8, 16, 32] {
            let lo = -(Int64(1) << (bits - 1)), hi = (Int64(1) << bits) - 1
            if v >= lo && v <= hi { return bits }
        }
        return 64
    }
}

// MARK: - Cross sections

enum SectionShape: String, CaseIterable, Identifiable {
    case rectangle = "Rectangle", hollowRectangle = "Hollow Rectangle", circle = "Circle", tube = "Circular Tube"
    case iBeam = "I-Beam", tee = "T-Section"
    var id: String { rawValue }

    /// Dimension names and labels, in order.
    var dimensions: [SectionDimension] {
        switch self {
        case .rectangle: return [SectionDimension(key: "b", label: "width b"), SectionDimension(key: "h", label: "height h")]
        case .hollowRectangle: return [SectionDimension(key: "b", label: "outer width b"), SectionDimension(key: "h", label: "outer height h"), SectionDimension(key: "t", label: "wall thickness t")]
        case .circle: return [SectionDimension(key: "d", label: "diameter d")]
        case .tube: return [SectionDimension(key: "D", label: "outer diameter D"), SectionDimension(key: "t", label: "wall thickness t")]
        case .iBeam: return [SectionDimension(key: "b", label: "flange width b"), SectionDimension(key: "h", label: "total height h"), SectionDimension(key: "tf", label: "flange thickness tf"), SectionDimension(key: "tw", label: "web thickness tw")]
        case .tee: return [SectionDimension(key: "b", label: "flange width b"), SectionDimension(key: "h", label: "total height h"), SectionDimension(key: "tf", label: "flange thickness tf"), SectionDimension(key: "tw", label: "web thickness tw")]
        }
    }
}

struct SectionDimension: Hashable {
    let key: String
    let label: String
}

/// Geometric properties of a cross-section (any consistent length unit).
struct SectionProperties: Equatable {
    var area: Double
    /// Centroid height from the bottom edge.
    var centroidY: Double
    var ix: Double     // about the horizontal centroidal axis
    var iy: Double     // about the vertical centroidal axis
    var height: Double
    var width: Double

    var sxTop: Double { ix / max(height - centroidY, 1e-300) }
    var sxBottom: Double { ix / max(centroidY, 1e-300) }
    /// Elastic section modulus (smaller of top/bottom).
    var sx: Double { min(sxTop, sxBottom) }
    var sy: Double { iy / (width / 2) }
    var rx: Double { (ix / area).squareRoot() }
    var ry: Double { (iy / area).squareRoot() }
    var polar: Double { ix + iy }

    enum SectionError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case let .invalid(s) = self { return s }; return nil }
    }

    /// Rectangles (width, height, bottom y) combined about a common centroid;
    /// negative width subtracts (holes).
    private static func composite(_ parts: [(b: Double, h: Double, y: Double)], width: Double, height: Double) -> SectionProperties {
        let area = parts.reduce(0) { $0 + $1.b * $1.h }
        let cy = parts.reduce(0) { $0 + $1.b * $1.h * ($1.y + $1.h / 2) } / area
        let ix = parts.reduce(0) { s, p in
            let a = p.b * p.h, d = p.y + p.h / 2 - cy
            return s + p.b * pow(p.h, 3) / 12 + a * d * d
        }
        let iy = parts.reduce(0) { s, p in s + p.h * pow(abs(p.b), 3) / 12 * (p.b < 0 ? -1 : 1) }
        return SectionProperties(area: area, centroidY: cy, ix: ix, iy: iy, height: height, width: width)
    }

    static func compute(_ shape: SectionShape, _ d: [String: Double]) throws -> SectionProperties {
        func v(_ k: String) throws -> Double {
            guard let x = d[k], x.isFinite, x > 0 else { throw SectionError.invalid("Enter a positive \(k)") }
            return x
        }
        switch shape {
        case .rectangle:
            let b = try v("b"), h = try v("h")
            return composite([(b, h, 0)], width: b, height: h)
        case .hollowRectangle:
            let b = try v("b"), h = try v("h"), t = try v("t")
            guard 2 * t < b, 2 * t < h else { throw SectionError.invalid("Wall is thicker than half the section") }
            return composite([(b, h, 0), (-(b - 2 * t), h - 2 * t, t)], width: b, height: h)
        case .circle:
            let dd = try v("d")
            let i = Double.pi * pow(dd, 4) / 64
            return SectionProperties(area: .pi * dd * dd / 4, centroidY: dd / 2, ix: i, iy: i, height: dd, width: dd)
        case .tube:
            let D = try v("D"), t = try v("t")
            guard 2 * t < D else { throw SectionError.invalid("Wall is thicker than the radius") }
            let di = D - 2 * t
            let i = Double.pi * (pow(D, 4) - pow(di, 4)) / 64
            return SectionProperties(area: .pi * (D * D - di * di) / 4, centroidY: D / 2, ix: i, iy: i, height: D, width: D)
        case .iBeam:
            let b = try v("b"), h = try v("h"), tf = try v("tf"), tw = try v("tw")
            guard 2 * tf < h, tw <= b else { throw SectionError.invalid("Flanges or web don't fit the section") }
            return composite([(b, tf, 0), (tw, h - 2 * tf, tf), (b, tf, h - tf)], width: b, height: h)
        case .tee:
            let b = try v("b"), h = try v("h"), tf = try v("tf"), tw = try v("tw")
            guard tf < h, tw <= b else { throw SectionError.invalid("Flange or web doesn't fit the section") }
            return composite([(tw, h - tf, 0), (b, tf, h - tf)], width: b, height: h)
        }
    }
}

// MARK: - Beams

/// Statically determinate beam analysis (simply supported or cantilever)
/// with point loads and distributed loads. Downward loads are positive;
/// sagging moment is positive; deflection is positive downward.
struct Beam {
    enum Support: String, CaseIterable, Identifiable {
        case simplySupported = "Simply Supported", cantilever = "Cantilever"
        var id: String { rawValue }
    }

    enum Load: Equatable {
        /// Force P at position a.
        case point(p: Double, a: Double)
        /// Uniform load w (force/length) from a to b.
        case distributed(w: Double, a: Double, b: Double)
        /// Applied moment (clockwise positive) at position a.
        case moment(m: Double, a: Double)
    }

    var support: Support
    var length: Double
    var loads: [Load]
    /// Flexural rigidity E·I (0 = skip deflection).
    var ei: Double = 0

    struct Results {
        /// Simply supported: left and right reactions; cantilever: wall force.
        var reactionLeft: Double
        var reactionRight: Double
        /// Fixed-end moment for a cantilever (hogging is negative).
        var fixedMoment: Double
        var x: [Double]
        var shear: [Double]
        var moment: [Double]
        var deflection: [Double]

        var maxMoment: (x: Double, value: Double) {
            let i = moment.indices.max { abs(moment[$0]) < abs(moment[$1]) } ?? 0
            return (x[i], moment[i])
        }
        var maxShear: Double { shear.map(abs).max() ?? 0 }
        var maxDeflection: (x: Double, value: Double) {
            let i = deflection.indices.max { abs(deflection[$0]) < abs(deflection[$1]) } ?? 0
            return (x.isEmpty ? 0 : x[i], deflection.isEmpty ? 0 : deflection[i])
        }
    }

    enum BeamError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case let .invalid(s) = self { return s }; return nil }
    }

    /// Total load and its moment about x = 0.
    private var resultant: (force: Double, momentAt0: Double) {
        var f = 0.0, m = 0.0
        for l in loads {
            switch l {
            case let .point(p, a): f += p; m += p * a
            case let .distributed(w, a, b):
                let lo = min(a, b), hi = max(a, b)
                f += w * (hi - lo); m += w * (hi - lo) * (lo + hi) / 2
            case let .moment(mm, _): m += mm   // clockwise moment pushes the right support down
            }
        }
        return (f, m)
    }

    func analyze(samples: Int = 401) throws -> Results {
        guard length > 0, length.isFinite else { throw BeamError.invalid("Enter a positive span") }
        for l in loads {
            switch l {
            case let .point(_, a), let .moment(_, a):
                guard (0...length).contains(a) else { throw BeamError.invalid("A load is outside the beam") }
            case let .distributed(_, a, b):
                guard (0...length).contains(a), (0...length).contains(b) else { throw BeamError.invalid("A load is outside the beam") }
            }
        }
        let (force, m0) = resultant
        var rl = 0.0, rr = 0.0, fixed = 0.0
        switch support {
        case .simplySupported:
            rr = m0 / length
            rl = force - rr
        case .cantilever:
            rl = force
            fixed = -m0      // reaction moment at the wall (hogging)
        }

        let xs = (0..<samples).map { length * Double($0) / Double(samples - 1) }
        var shear: [Double] = [], moment: [Double] = []
        for x in xs {
            // Sum of everything strictly left of the section (point loads at x count as applied).
            var v = rl, m = rl * x + fixed
            for l in loads {
                switch l {
                case let .point(p, a):
                    if a < x || (a == x && x == length) || (a == 0 && x == 0 && support == .cantilever) {
                        v -= p; m -= p * (x - a)
                    }
                case let .distributed(w, a, b):
                    let lo = min(a, b), hi = min(max(a, b), x)
                    if hi > lo {
                        let len = hi - lo
                        v -= w * len
                        m -= w * len * (x - (lo + hi) / 2)
                    }
                case let .moment(mm, a):
                    if a < x { m += mm }
                }
            }
            if support == .simplySupported, x == length { v += rr }   // right reaction closes the diagram
            shear.append(v); moment.append(m)
        }

        var deflection: [Double] = []
        if ei > 0 {
            // EI·y'' = −M (y positive down → y'' = M/EI with sagging positive). Integrate twice.
            let h = length / Double(samples - 1)
            var slope = [0.0], defl = [0.0]
            for i in 1..<samples {
                slope.append(slope[i - 1] + (moment[i - 1] + moment[i]) / 2 * h / ei)
            }
            for i in 1..<samples {
                defl.append(defl[i - 1] + (slope[i - 1] + slope[i]) / 2 * h)
            }
            // Boundary conditions: cantilever y(0)=y'(0)=0 (already); simply
            // supported y(0)=y(L)=0 → remove the linear part.
            if support == .simplySupported, let last = defl.last {
                defl = defl.enumerated().map { i, y in y - last * xs[i] / length }
            }
            // With sagging positive, y computed this way is upward; flip so down is positive.
            deflection = defl.map { -$0 }
        }
        return Results(reactionLeft: rl, reactionRight: rr, fixedMoment: fixed, x: xs, shear: shear,
                       moment: moment, deflection: deflection)
    }
}
