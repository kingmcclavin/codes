import Foundation

enum AngleMode: String, Codable, CaseIterable, Identifiable {
    case degrees, radians
    var id: String { rawValue }
    var label: String { self == .degrees ? "DEG" : "RAD" }
}

// MARK: - Functions

enum MathFunctions {
    private static let aliases: [String: String] = [
        "arcsin": "asin", "arccos": "acos", "arctan": "atan", "sin⁻¹": "asin",
        "log10": "log", "sqr": "sqrt", "√": "sqrt", "fabs": "abs",
    ]

    static let names: Set<String> = [
        "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "sinh", "cosh", "tanh",
        "sec", "csc", "cot",
        "sqrt", "cbrt", "root", "abs", "log", "ln", "log2", "logb", "exp",
        "floor", "ceil", "round", "sign", "min", "max", "fact", "nCr", "nPr",
        "deg", "rad", "hypot", "avg", "sum", "mod",
    ]

    static func canonicalName(_ name: String) -> String { aliases[name] ?? name }
    static func isFunction(_ name: String) -> Bool { names.contains(canonicalName(name)) }

    /// Short descriptions shown in the function picker.
    static let catalog: [(name: String, insert: String, help: String)] = [
        ("sin", "sin(", "Sine"), ("cos", "cos(", "Cosine"), ("tan", "tan(", "Tangent"),
        ("asin", "asin(", "Inverse sine"), ("acos", "acos(", "Inverse cosine"), ("atan", "atan(", "Inverse tangent"),
        ("atan2", "atan2(", "atan2(y, x) – angle of a vector"),
        ("sinh", "sinh(", "Hyperbolic sine"), ("cosh", "cosh(", "Hyperbolic cosine"), ("tanh", "tanh(", "Hyperbolic tangent"),
        ("sqrt", "sqrt(", "Square root"), ("cbrt", "cbrt(", "Cube root"), ("root", "root(", "root(x, n) – n-th root"),
        ("abs", "abs(", "Absolute value"), ("log", "log(", "Base-10 logarithm"), ("ln", "ln(", "Natural logarithm"),
        ("log2", "log2(", "Base-2 logarithm"), ("logb", "logb(", "logb(x, b) – logarithm base b"), ("exp", "exp(", "e to the power x"),
        ("floor", "floor(", "Round down"), ("ceil", "ceil(", "Round up"), ("round", "round(", "round(x) or round(x, digits)"),
        ("min", "min(", "Smallest argument"), ("max", "max(", "Largest argument"), ("avg", "avg(", "Average of arguments"),
        ("sum", "sum(", "Sum of arguments"), ("hypot", "hypot(", "√(a² + b² + …)"), ("mod", "mod(", "mod(a, b) – remainder"),
        ("fact", "fact(", "Factorial (also n!)"), ("nCr", "nCr(", "Combinations"), ("nPr", "nPr(", "Permutations"),
        ("deg", "deg(", "Radians → degrees"), ("rad", "rad(", "Degrees → radians"),
    ]
}

// MARK: - Constants

struct PhysicalConstant: Identifiable {
    /// Identifier used in expressions.
    var id: String
    var symbol: String
    var name: String
    var value: Double
    var unit: String
}

enum Constants {
    /// π and e are always available. The others use distinct identifiers so
    /// they never collide with common variable names (c, g, h, k, R …).
    static let all: [PhysicalConstant] = [
        PhysicalConstant(id: "π", symbol: "π", name: "Pi", value: .pi, unit: ""),
        PhysicalConstant(id: "e", symbol: "e", name: "Euler's number", value: M_E, unit: ""),
        PhysicalConstant(id: "g0", symbol: "g₀", name: "Standard gravity", value: 9.80665, unit: "m/s²"),
        PhysicalConstant(id: "c0", symbol: "c", name: "Speed of light", value: 299_792_458, unit: "m/s"),
        PhysicalConstant(id: "G_N", symbol: "G", name: "Gravitational constant", value: 6.67430e-11, unit: "N·m²/kg²"),
        PhysicalConstant(id: "h_P", symbol: "h", name: "Planck constant", value: 6.62607015e-34, unit: "J·s"),
        PhysicalConstant(id: "ħ", symbol: "ħ", name: "Reduced Planck constant", value: 1.054571817e-34, unit: "J·s"),
        PhysicalConstant(id: "k_B", symbol: "k", name: "Boltzmann constant", value: 1.380649e-23, unit: "J/K"),
        PhysicalConstant(id: "N_A", symbol: "Nₐ", name: "Avogadro constant", value: 6.02214076e23, unit: "1/mol"),
        PhysicalConstant(id: "R_u", symbol: "R", name: "Universal gas constant", value: 8.314462618, unit: "J/(mol·K)"),
        PhysicalConstant(id: "q_e", symbol: "e", name: "Elementary charge", value: 1.602176634e-19, unit: "C"),
        PhysicalConstant(id: "m_e", symbol: "mₑ", name: "Electron mass", value: 9.1093837015e-31, unit: "kg"),
        PhysicalConstant(id: "m_p", symbol: "mₚ", name: "Proton mass", value: 1.67262192369e-27, unit: "kg"),
        PhysicalConstant(id: "ε0", symbol: "ε₀", name: "Vacuum permittivity", value: 8.8541878128e-12, unit: "F/m"),
        PhysicalConstant(id: "μ0", symbol: "μ₀", name: "Vacuum permeability", value: 1.25663706212e-6, unit: "N/A²"),
        PhysicalConstant(id: "σ_SB", symbol: "σ", name: "Stefan–Boltzmann constant", value: 5.670374419e-8, unit: "W/(m²·K⁴)"),
        PhysicalConstant(id: "atm0", symbol: "atm", name: "Standard atmosphere", value: 101_325, unit: "Pa"),
    ]

    private static let byID: [String: Double] = {
        var d = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.value) })
        d["pi"] = .pi
        d["eps0"] = 8.8541878128e-12
        d["mu0"] = 1.25663706212e-6
        return d
    }()

    static func value(_ name: String) -> Double? { byID[name] }
    static func isConstant(_ name: String) -> Bool { byID[name] != nil }
}

// MARK: - Evaluator

/// Evaluates a syntax tree. Name lookup is delegated so the same evaluator
/// serves the calculator, saved formulas, tools and data tables.
struct ExpressionEvaluator {
    var angleMode: AngleMode
    /// Returns a value for a free name, or nil if unknown.
    var resolve: (String) throws -> Double?

    func evaluate(_ e: Expr) throws -> Double {
        let v = try eval(e)
        guard v.isFinite else { throw CalcError.notFinite }
        return v
    }

    private func eval(_ e: Expr) throws -> Double {
        switch e {
        case let .number(v):
            return v
        case let .variable(name):
            if let v = try resolve(name) { return v }
            if let c = Constants.value(name) { return c }
            throw CalcError.missingVariable(name)
        case let .negate(x):
            return -(try eval(x))
        case let .binary(op, l, r):
            let a = try eval(l), b = try eval(r)
            switch op {
            case "+": return try finite(a + b)
            case "-": return try finite(a - b)
            case "*": return try finite(a * b)
            case "/":
                guard b != 0 else { throw CalcError.divisionByZero }
                return try finite(a / b)
            case "^":
                if a < 0 && b != b.rounded() {
                    // Allow odd roots of negatives: (-8)^(1/3) = -2
                    let inv = 1 / b
                    if abs(inv - inv.rounded()) < 1e-9, Int(inv.rounded()) % 2 != 0 {
                        return -pow(-a, b)
                    }
                    throw CalcError.domain("A negative number can't be raised to a fractional power")
                }
                if a == 0 && b < 0 { throw CalcError.divisionByZero }
                return try finite(pow(a, b))
            default:
                throw CalcError.invalidExpression("unknown operator \(op)")
            }
        case let .postfix(op, x):
            let v = try eval(x)
            switch op {
            case "!": return try factorial(v)
            case "%": return v / 100
            case "°": return angleMode == .radians ? v * .pi / 180 : v
            default: throw CalcError.invalidExpression("unknown operator \(op)")
            }
        case let .call(name, args):
            return try call(name, try args.map(eval))
        }
    }

    private func finite(_ v: Double) throws -> Double {
        guard v.isFinite else { throw CalcError.notFinite }
        return v
    }

    private func factorial(_ v: Double) throws -> Double {
        guard v >= 0, v == v.rounded() else { throw CalcError.domain("Factorial requires a non-negative whole number") }
        guard v <= 170 else { throw CalcError.notFinite }
        return (0..<Int(v)).reduce(1.0) { $0 * Double($1 + 1) }
    }

    // Trig helpers: exact values at multiples of 90° and tiny-noise cleanup.
    private func toRadians(_ x: Double) -> Double { angleMode == .degrees ? x * .pi / 180 : x }
    private func fromRadians(_ x: Double) -> Double { angleMode == .degrees ? x * 180 / .pi : x }

    private func exactQuarterTurns(_ x: Double) -> Int? {
        let quarter = angleMode == .degrees ? x / 90 : x / (.pi / 2)
        let r = quarter.rounded()
        guard abs(quarter - r) < 1e-12 else { return nil }
        let m = Int(r.truncatingRemainder(dividingBy: 4))
        return (m + 4) % 4
    }

    private func clean(_ v: Double) -> Double { abs(v) < 1e-15 ? 0 : v }

    private func call(_ name: String, _ a: [Double]) throws -> Double {
        func need(_ n: Int) throws {
            guard a.count == n else {
                throw CalcError.argumentCount(function: name, expected: n == 1 ? "1 argument" : "\(n) arguments")
            }
        }
        func atLeast(_ n: Int) throws {
            guard a.count >= n else { throw CalcError.argumentCount(function: name, expected: "at least \(n) argument\(n == 1 ? "" : "s")") }
        }
        switch name {
        case "sin":
            try need(1)
            if let q = exactQuarterTurns(a[0]) { return [0, 1, 0, -1][q] }
            return clean(sin(toRadians(a[0])))
        case "cos":
            try need(1)
            if let q = exactQuarterTurns(a[0]) { return [1, 0, -1, 0][q] }
            return clean(cos(toRadians(a[0])))
        case "tan":
            try need(1)
            if let q = exactQuarterTurns(a[0]) {
                if q % 2 == 1 { throw CalcError.domain("tan is undefined at \(angleMode == .degrees ? "90°" : "π/2") + k·\(angleMode == .degrees ? "180°" : "π")") }
                return 0
            }
            return clean(tan(toRadians(a[0])))
        case "sec": try need(1); let c = try call("cos", a); guard c != 0 else { throw CalcError.divisionByZero }; return 1 / c
        case "csc": try need(1); let s = try call("sin", a); guard s != 0 else { throw CalcError.divisionByZero }; return 1 / s
        case "cot": try need(1); let t = try call("tan", a); guard t != 0 else { throw CalcError.divisionByZero }; return 1 / t
        case "asin":
            try need(1)
            guard (-1...1).contains(a[0]) else { throw CalcError.domain("asin requires a value between -1 and 1") }
            return fromRadians(asin(a[0]))
        case "acos":
            try need(1)
            guard (-1...1).contains(a[0]) else { throw CalcError.domain("acos requires a value between -1 and 1") }
            return fromRadians(acos(a[0]))
        case "atan": try need(1); return fromRadians(atan(a[0]))
        case "atan2": try need(2); return fromRadians(atan2(a[0], a[1]))
        case "sinh": try need(1); return try finite(sinh(a[0]))
        case "cosh": try need(1); return try finite(cosh(a[0]))
        case "tanh": try need(1); return tanh(a[0])
        case "sqrt":
            try need(1)
            guard a[0] >= 0 else { throw CalcError.domain("Square root requires a non-negative value") }
            return sqrt(a[0])
        case "cbrt": try need(1); return cbrt(a[0])
        case "root":
            try need(2)
            guard a[1] != 0 else { throw CalcError.domain("root(x, n) requires n ≠ 0") }
            return try eval(.binary("^", .number(a[0]), .number(1 / a[1])))
        case "abs": try need(1); return abs(a[0])
        case "log":
            if a.count == 2 { return try call("logb", a) }
            try need(1)
            guard a[0] > 0 else { throw CalcError.domain("log requires a positive value") }
            return log10(a[0])
        case "ln":
            try need(1)
            guard a[0] > 0 else { throw CalcError.domain("ln requires a positive value") }
            return log(a[0])
        case "log2":
            try need(1)
            guard a[0] > 0 else { throw CalcError.domain("log2 requires a positive value") }
            return log2(a[0])
        case "logb":
            try need(2)
            guard a[0] > 0, a[1] > 0, a[1] != 1 else { throw CalcError.domain("logb(x, b) requires x > 0 and b > 0, b ≠ 1") }
            return log(a[0]) / log(a[1])
        case "exp": try need(1); return try finite(exp(a[0]))
        case "floor": try need(1); return floor(a[0])
        case "ceil": try need(1); return ceil(a[0])
        case "round":
            if a.count == 2 {
                let f = pow(10, a[1].rounded())
                return (a[0] * f).rounded() / f
            }
            try need(1); return a[0].rounded()
        case "sign": try need(1); return a[0] > 0 ? 1 : (a[0] < 0 ? -1 : 0)
        case "min": try atLeast(1); return a.min()!
        case "max": try atLeast(1); return a.max()!
        case "sum": try atLeast(1); return a.reduce(0, +)
        case "avg": try atLeast(1); return a.reduce(0, +) / Double(a.count)
        case "hypot": try atLeast(1); return sqrt(a.reduce(0) { $0 + $1 * $1 })
        case "mod":
            try need(2)
            guard a[1] != 0 else { throw CalcError.divisionByZero }
            let r = a[0].truncatingRemainder(dividingBy: a[1])
            return r < 0 ? r + abs(a[1]) : r
        case "fact": try need(1); return try factorial(a[0])
        case "nCr", "nPr":
            try need(2)
            let n = a[0], r = a[1]
            guard n >= 0, r >= 0, r <= n, n == n.rounded(), r == r.rounded() else {
                throw CalcError.domain("\(name) requires whole numbers with 0 ≤ r ≤ n")
            }
            var result = 1.0
            for i in 0..<Int(r) { result *= (n - Double(i)) }
            if name == "nCr" { result /= try factorial(r) }
            return try finite(result.rounded())
        case "deg": try need(1); return a[0] * 180 / .pi
        case "rad": try need(1); return a[0] * .pi / 180
        default:
            throw CalcError.unknownFunction(name)
        }
    }
}

// MARK: - Number formatting

enum NumberFormatting {
    /// Up to `digits` significant digits; scientific notation for very large
    /// or very small magnitudes (shown as 6.674 × 10⁻¹¹).
    static func format(_ v: Double, digits: Int = 10, pretty: Bool = true) -> String {
        guard v.isFinite else { return v.isNaN ? "undefined" : (v > 0 ? "∞" : "−∞") }
        if v == 0 { return "0" }
        let a = abs(v)
        if a >= 1e10 || a < 1e-4 {
            let exponent = Int(floor(log10(a)))
            var mantissa = v / pow(10, Double(exponent))
            // Guard against 9.9999999 → 10.0 after rounding.
            let rounded = (mantissa * 1e6).rounded() / 1e6
            var exp = exponent
            if abs(rounded) >= 10 { mantissa = rounded / 10; exp += 1 } else { mantissa = rounded }
            let m = trim(String(format: "%.6f", mantissa))
            return pretty ? "\(m) × 10\(superscript(exp))" : "\(m)e\(exp)"
        }
        let s = String(format: "%.\(digits)g", v)
        if s.contains("e") { return s }
        return trim(s)
    }

    /// Plain form suitable for typing back into an expression (1.5e-7).
    static func plain(_ v: Double) -> String { format(v, digits: 12, pretty: false) }

    private static func trim(_ s: String) -> String {
        guard s.contains(".") else { return s }
        var t = s
        while t.hasSuffix("0") { t.removeLast() }
        if t.hasSuffix(".") { t.removeLast() }
        return t
    }

    static func superscript(_ n: Int) -> String {
        let map: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        return String(String(n).map { map[$0] ?? $0 })
    }
}
