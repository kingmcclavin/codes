import Foundation

// MARK: - Dimensions

/// Exponents of the SI base dimensions: length, mass, time, current,
/// temperature, amount. `kg·m²/s²` = [2, 1, -2, 0, 0, 0].
struct UnitDimension: Hashable {
    var exponents: [Int]

    static let count = 6
    static let symbols = ["m", "kg", "s", "A", "K", "mol"]
    static let none = UnitDimension([0, 0, 0, 0, 0, 0])

    init(_ e: [Int]) { exponents = e }

    static func base(_ index: Int, _ power: Int = 1) -> UnitDimension {
        var e = Array(repeating: 0, count: count)
        e[index] = power
        return UnitDimension(e)
    }

    var isDimensionless: Bool { exponents.allSatisfy { $0 == 0 } }

    static func * (a: UnitDimension, b: UnitDimension) -> UnitDimension { UnitDimension(zip(a.exponents, b.exponents).map(+)) }
    static func / (a: UnitDimension, b: UnitDimension) -> UnitDimension { UnitDimension(zip(a.exponents, b.exponents).map(-)) }
    func power(_ n: Int) -> UnitDimension { UnitDimension(exponents.map { $0 * n }) }

    /// Integer root, or nil if an exponent isn't divisible (√m).
    func root(_ n: Int) -> UnitDimension? {
        guard n != 0, exponents.allSatisfy({ $0 % n == 0 }) else { return nil }
        return UnitDimension(exponents.map { $0 / n })
    }

    /// SI form such as `kg·m²/s²`, followed by a named unit if one matches (J).
    var description: String {
        if isDimensionless { return "dimensionless" }
        func part(_ positive: Bool) -> String {
            // Conventional order: kg·m²/s², not m²·kg/s².
            [1, 0, 2, 3, 4, 5].compactMap { i -> String? in
                let sym = UnitDimension.symbols[i], e = exponents[i]
                guard positive ? e > 0 : e < 0 else { return nil }
                let p = abs(e)
                return p == 1 ? sym : sym + NumberFormatting.superscript(p)
            }.joined(separator: "·")
        }
        let num = part(true), den = part(false)
        let si = den.isEmpty ? num : "\(num.isEmpty ? "1" : num)/\(den)"
        if let named = UnitLibrary.namedUnit(for: self), named != si { return "\(si) (\(named))" }
        return si
    }
}

// MARK: - Units

enum UnitCategory: String, CaseIterable, Identifiable {
    case length = "Length", area = "Area", volume = "Volume", mass = "Mass", time = "Time"
    case speed = "Speed", acceleration = "Acceleration", force = "Force", energy = "Energy", power = "Power"
    case pressure = "Pressure", temperature = "Temperature", torque = "Torque", density = "Density"
    case current = "Current", voltage = "Voltage", resistance = "Resistance", charge = "Charge"
    case capacitance = "Capacitance", frequency = "Frequency", angle = "Angle"
    var id: String { rawValue }
}

/// A concrete unit: value_SI = value × scale + offset.
struct UnitDef: Identifiable, Hashable {
    var symbol: String
    var name: String
    var category: UnitCategory
    var dimension: UnitDimension
    var scale: Double
    var offset: Double = 0
    var id: String { symbol }
}

/// A parsed (possibly compound) unit such as `kg·m/s²`.
struct UnitSpec: Equatable {
    var dimension: UnitDimension
    var scale: Double
    var offset: Double = 0

    static let one = UnitSpec(dimension: .none, scale: 1)
}

enum UnitLibrary {
    private static let L = UnitDimension.base(0), M = UnitDimension.base(1), T = UnitDimension.base(2)
    private static let I = UnitDimension.base(3), Θ = UnitDimension.base(4), N = UnitDimension.base(5)

    private static let force = M * L / T.power(2)
    private static let energy = force * L
    private static let powerDim = energy / T
    private static let pressure = force / L.power(2)
    private static let charge = I * T
    private static let voltage = powerDim / I

    static let all: [UnitDef] = [
        // Length
        UnitDef(symbol: "nm", name: "nanometre", category: .length, dimension: L, scale: 1e-9),
        UnitDef(symbol: "µm", name: "micrometre", category: .length, dimension: L, scale: 1e-6),
        UnitDef(symbol: "mm", name: "millimetre", category: .length, dimension: L, scale: 1e-3),
        UnitDef(symbol: "cm", name: "centimetre", category: .length, dimension: L, scale: 1e-2),
        UnitDef(symbol: "m", name: "metre", category: .length, dimension: L, scale: 1),
        UnitDef(symbol: "km", name: "kilometre", category: .length, dimension: L, scale: 1e3),
        UnitDef(symbol: "in", name: "inch", category: .length, dimension: L, scale: 0.0254),
        UnitDef(symbol: "ft", name: "foot", category: .length, dimension: L, scale: 0.3048),
        UnitDef(symbol: "yd", name: "yard", category: .length, dimension: L, scale: 0.9144),
        UnitDef(symbol: "mi", name: "mile", category: .length, dimension: L, scale: 1609.344),
        // Area
        UnitDef(symbol: "mm²", name: "square millimetre", category: .area, dimension: L.power(2), scale: 1e-6),
        UnitDef(symbol: "cm²", name: "square centimetre", category: .area, dimension: L.power(2), scale: 1e-4),
        UnitDef(symbol: "m²", name: "square metre", category: .area, dimension: L.power(2), scale: 1),
        UnitDef(symbol: "in²", name: "square inch", category: .area, dimension: L.power(2), scale: 0.00064516),
        UnitDef(symbol: "ft²", name: "square foot", category: .area, dimension: L.power(2), scale: 0.09290304),
        // Volume
        UnitDef(symbol: "mL", name: "millilitre", category: .volume, dimension: L.power(3), scale: 1e-6),
        UnitDef(symbol: "L", name: "litre", category: .volume, dimension: L.power(3), scale: 1e-3),
        UnitDef(symbol: "m³", name: "cubic metre", category: .volume, dimension: L.power(3), scale: 1),
        UnitDef(symbol: "in³", name: "cubic inch", category: .volume, dimension: L.power(3), scale: 1.6387064e-5),
        UnitDef(symbol: "ft³", name: "cubic foot", category: .volume, dimension: L.power(3), scale: 0.028316846592),
        UnitDef(symbol: "gal", name: "US gallon", category: .volume, dimension: L.power(3), scale: 0.003785411784),
        // Mass
        UnitDef(symbol: "mg", name: "milligram", category: .mass, dimension: M, scale: 1e-6),
        UnitDef(symbol: "g", name: "gram", category: .mass, dimension: M, scale: 1e-3),
        UnitDef(symbol: "kg", name: "kilogram", category: .mass, dimension: M, scale: 1),
        UnitDef(symbol: "t", name: "tonne", category: .mass, dimension: M, scale: 1000),
        UnitDef(symbol: "oz", name: "ounce", category: .mass, dimension: M, scale: 0.028349523125),
        UnitDef(symbol: "lb", name: "pound", category: .mass, dimension: M, scale: 0.45359237),
        // Time
        UnitDef(symbol: "ms", name: "millisecond", category: .time, dimension: T, scale: 1e-3),
        UnitDef(symbol: "s", name: "second", category: .time, dimension: T, scale: 1),
        UnitDef(symbol: "min", name: "minute", category: .time, dimension: T, scale: 60),
        UnitDef(symbol: "hr", name: "hour", category: .time, dimension: T, scale: 3600),
        UnitDef(symbol: "day", name: "day", category: .time, dimension: T, scale: 86400),
        // Speed
        UnitDef(symbol: "m/s", name: "metre per second", category: .speed, dimension: L / T, scale: 1),
        UnitDef(symbol: "km/h", name: "kilometre per hour", category: .speed, dimension: L / T, scale: 1 / 3.6),
        UnitDef(symbol: "mph", name: "mile per hour", category: .speed, dimension: L / T, scale: 0.44704),
        UnitDef(symbol: "ft/s", name: "foot per second", category: .speed, dimension: L / T, scale: 0.3048),
        UnitDef(symbol: "kn", name: "knot", category: .speed, dimension: L / T, scale: 1852.0 / 3600),
        // Acceleration
        UnitDef(symbol: "m/s²", name: "metre per second squared", category: .acceleration, dimension: L / T.power(2), scale: 1),
        UnitDef(symbol: "ft/s²", name: "foot per second squared", category: .acceleration, dimension: L / T.power(2), scale: 0.3048),
        UnitDef(symbol: "gₙ", name: "standard gravity", category: .acceleration, dimension: L / T.power(2), scale: 9.80665),
        // Force
        UnitDef(symbol: "N", name: "newton", category: .force, dimension: force, scale: 1),
        UnitDef(symbol: "kN", name: "kilonewton", category: .force, dimension: force, scale: 1e3),
        UnitDef(symbol: "lbf", name: "pound-force", category: .force, dimension: force, scale: 4.4482216152605),
        UnitDef(symbol: "kip", name: "kip", category: .force, dimension: force, scale: 4448.2216152605),
        // Energy
        UnitDef(symbol: "J", name: "joule", category: .energy, dimension: energy, scale: 1),
        UnitDef(symbol: "kJ", name: "kilojoule", category: .energy, dimension: energy, scale: 1e3),
        UnitDef(symbol: "MJ", name: "megajoule", category: .energy, dimension: energy, scale: 1e6),
        UnitDef(symbol: "cal", name: "calorie", category: .energy, dimension: energy, scale: 4.184),
        UnitDef(symbol: "kcal", name: "kilocalorie", category: .energy, dimension: energy, scale: 4184),
        UnitDef(symbol: "ft·lbf", name: "foot-pound", category: .energy, dimension: energy, scale: 1.3558179483314),
        UnitDef(symbol: "Wh", name: "watt-hour", category: .energy, dimension: energy, scale: 3600),
        UnitDef(symbol: "kWh", name: "kilowatt-hour", category: .energy, dimension: energy, scale: 3.6e6),
        UnitDef(symbol: "BTU", name: "British thermal unit", category: .energy, dimension: energy, scale: 1055.05585262),
        UnitDef(symbol: "eV", name: "electronvolt", category: .energy, dimension: energy, scale: 1.602176634e-19),
        // Power
        UnitDef(symbol: "W", name: "watt", category: .power, dimension: powerDim, scale: 1),
        UnitDef(symbol: "kW", name: "kilowatt", category: .power, dimension: powerDim, scale: 1e3),
        UnitDef(symbol: "MW", name: "megawatt", category: .power, dimension: powerDim, scale: 1e6),
        UnitDef(symbol: "hp", name: "horsepower", category: .power, dimension: powerDim, scale: 745.69987158227),
        // Pressure
        UnitDef(symbol: "Pa", name: "pascal", category: .pressure, dimension: pressure, scale: 1),
        UnitDef(symbol: "kPa", name: "kilopascal", category: .pressure, dimension: pressure, scale: 1e3),
        UnitDef(symbol: "MPa", name: "megapascal", category: .pressure, dimension: pressure, scale: 1e6),
        UnitDef(symbol: "GPa", name: "gigapascal", category: .pressure, dimension: pressure, scale: 1e9),
        UnitDef(symbol: "bar", name: "bar", category: .pressure, dimension: pressure, scale: 1e5),
        UnitDef(symbol: "psi", name: "pound per square inch", category: .pressure, dimension: pressure, scale: 6894.757293168),
        UnitDef(symbol: "ksi", name: "kip per square inch", category: .pressure, dimension: pressure, scale: 6894757.293168),
        UnitDef(symbol: "atm", name: "atmosphere", category: .pressure, dimension: pressure, scale: 101325),
        // Temperature
        UnitDef(symbol: "K", name: "kelvin", category: .temperature, dimension: Θ, scale: 1),
        UnitDef(symbol: "°C", name: "degree Celsius", category: .temperature, dimension: Θ, scale: 1, offset: 273.15),
        UnitDef(symbol: "°F", name: "degree Fahrenheit", category: .temperature, dimension: Θ, scale: 5.0 / 9, offset: 459.67 * 5 / 9),
        // Torque
        UnitDef(symbol: "N·m", name: "newton-metre", category: .torque, dimension: energy, scale: 1),
        UnitDef(symbol: "lbf·ft", name: "pound-foot", category: .torque, dimension: energy, scale: 1.3558179483314),
        UnitDef(symbol: "lbf·in", name: "pound-inch", category: .torque, dimension: energy, scale: 0.1129848290276),
        // Density
        UnitDef(symbol: "kg/m³", name: "kilogram per cubic metre", category: .density, dimension: M / L.power(3), scale: 1),
        UnitDef(symbol: "g/cm³", name: "gram per cubic centimetre", category: .density, dimension: M / L.power(3), scale: 1000),
        UnitDef(symbol: "lb/ft³", name: "pound per cubic foot", category: .density, dimension: M / L.power(3), scale: 16.018463373960138),
        // Electrical
        UnitDef(symbol: "mA", name: "milliampere", category: .current, dimension: I, scale: 1e-3),
        UnitDef(symbol: "A", name: "ampere", category: .current, dimension: I, scale: 1),
        UnitDef(symbol: "mV", name: "millivolt", category: .voltage, dimension: voltage, scale: 1e-3),
        UnitDef(symbol: "V", name: "volt", category: .voltage, dimension: voltage, scale: 1),
        UnitDef(symbol: "kV", name: "kilovolt", category: .voltage, dimension: voltage, scale: 1e3),
        UnitDef(symbol: "Ω", name: "ohm", category: .resistance, dimension: voltage / I, scale: 1),
        UnitDef(symbol: "kΩ", name: "kiloohm", category: .resistance, dimension: voltage / I, scale: 1e3),
        UnitDef(symbol: "MΩ", name: "megaohm", category: .resistance, dimension: voltage / I, scale: 1e6),
        UnitDef(symbol: "C", name: "coulomb", category: .charge, dimension: charge, scale: 1),
        UnitDef(symbol: "mAh", name: "milliampere-hour", category: .charge, dimension: charge, scale: 3.6),
        UnitDef(symbol: "F", name: "farad", category: .capacitance, dimension: charge / voltage, scale: 1),
        UnitDef(symbol: "µF", name: "microfarad", category: .capacitance, dimension: charge / voltage, scale: 1e-6),
        UnitDef(symbol: "nF", name: "nanofarad", category: .capacitance, dimension: charge / voltage, scale: 1e-9),
        UnitDef(symbol: "pF", name: "picofarad", category: .capacitance, dimension: charge / voltage, scale: 1e-12),
        UnitDef(symbol: "Hz", name: "hertz", category: .frequency, dimension: UnitDimension.none / T, scale: 1),
        UnitDef(symbol: "kHz", name: "kilohertz", category: .frequency, dimension: UnitDimension.none / T, scale: 1e3),
        UnitDef(symbol: "rpm", name: "revolution per minute", category: .frequency, dimension: UnitDimension.none / T, scale: 1.0 / 60),
        // Angle (dimensionless)
        UnitDef(symbol: "rad", name: "radian", category: .angle, dimension: .none, scale: 1),
        UnitDef(symbol: "°", name: "degree", category: .angle, dimension: .none, scale: .pi / 180),
    ]

    /// Extra unit symbols that are understood but not listed in pickers.
    private static let extras: [String: UnitSpec] = [
        "h": UnitSpec(dimension: T, scale: 3600),
        "mol": UnitSpec(dimension: N, scale: 1),
        "kmol": UnitSpec(dimension: N, scale: 1000),
        "kg·m/s": UnitSpec(dimension: M * L / T, scale: 1),
        "J·s": UnitSpec(dimension: energy * T, scale: 1),
        "ohm": UnitSpec(dimension: voltage / I, scale: 1),
        "um": UnitSpec(dimension: L, scale: 1e-6),
        "deg": UnitSpec(dimension: .none, scale: .pi / 180),
        "degC": UnitSpec(dimension: Θ, scale: 1, offset: 273.15),
        "degF": UnitSpec(dimension: Θ, scale: 5.0 / 9, offset: 459.67 * 5 / 9),
        "T": UnitSpec(dimension: M / (T.power(2) * I), scale: 1),     // tesla
        "Wb": UnitSpec(dimension: energy / I, scale: 1),               // weber
        "H": UnitSpec(dimension: energy / I.power(2), scale: 1),        // henry
        "S": UnitSpec(dimension: I / voltage, scale: 1),               // siemens
        "lbm": UnitSpec(dimension: M, scale: 0.45359237),
    ]

    private static let bySymbol: [String: UnitDef] = Dictionary(all.map { ($0.symbol, $0) }, uniquingKeysWith: { a, _ in a })

    static func units(in category: UnitCategory) -> [UnitDef] { all.filter { $0.category == category } }

    static func def(_ symbol: String) -> UnitDef? { bySymbol[symbol] }

    /// Named units used to describe a dimension (first match wins).
    static func namedUnit(for d: UnitDimension) -> String? {
        let preferred = ["N", "J", "W", "Pa", "V", "Ω", "C", "F", "Hz", "m/s", "m/s²", "kg", "m", "s", "K", "A", "m²", "m³", "kg/m³"]
        for s in preferred { if let u = bySymbol[s], u.dimension == d { return s } }
        return nil
    }

    /// Units that a value with this unit can be shown in.
    static func compatibleUnits(with unit: String) -> [UnitDef] {
        guard let spec = parse(unit) else { return [] }
        var result = all.filter { $0.dimension == spec.dimension && $0.category != .angle }
        // Energy and torque share a dimension; keep the declared unit's family first.
        if let cat = def(unit)?.category {
            result = result.filter { $0.category == cat } + result.filter { $0.category != cat }
        }
        if !result.contains(where: { $0.symbol == unit }) {
            result.insert(UnitDef(symbol: unit, name: unit, category: .length, dimension: spec.dimension, scale: spec.scale), at: 0)
        }
        return result
    }

    // MARK: Parsing

    private static let prefixes: [Character: Double] = [
        "G": 1e9, "M": 1e6, "k": 1e3, "c": 1e-2, "m": 1e-3, "µ": 1e-6, "μ": 1e-6, "u": 1e-6, "n": 1e-9, "p": 1e-12,
    ]
    private static let prefixable: Set<String> = ["m", "g", "s", "N", "J", "W", "Pa", "A", "V", "Ω", "F", "Hz", "C", "L", "eV", "mol", "T", "H"]

    private static func atom(_ symbol: String) -> UnitSpec? {
        if let u = bySymbol[symbol] { return UnitSpec(dimension: u.dimension, scale: u.scale, offset: u.offset) }
        if let u = extras[symbol] { return u }
        if let p = symbol.first, let factor = prefixes[p] {
            let rest = String(symbol.dropFirst())
            if prefixable.contains(rest), let base = atom(rest), base.offset == 0 {
                return UnitSpec(dimension: base.dimension, scale: base.scale * factor)
            }
        }
        return nil
    }

    /// Parses unit strings such as `kg`, `m/s²`, `kg·m^2/s^2`, `J/(mol·K)`,
    /// `N*m`, `1/s`. Returns nil for unknown units. Empty means dimensionless.
    static func parse(_ text: String) -> UnitSpec? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return .one }
        if let whole = atom(t) { return whole }   // includes °C, ft·lbf, km/h …
        var p = UnitParser(chars: Array(t))
        guard let spec = p.parseProduct(), p.index == p.chars.count else { return nil }
        return spec
    }

    private struct UnitParser {
        let chars: [Character]
        var index = 0

        mutating func parseProduct() -> UnitSpec? {
            guard var result = parseFactor() else { return nil }
            while index < chars.count {
                let c = chars[index]
                if c == ")" { break }
                if c == "/" {
                    index += 1
                    guard let f = parseFactor() else { return nil }
                    result = UnitSpec(dimension: result.dimension / f.dimension, scale: result.scale / f.scale)
                } else if "·*⋅ ".contains(c) {
                    index += 1
                    guard let f = parseFactor() else { return nil }
                    result = UnitSpec(dimension: result.dimension * f.dimension, scale: result.scale * f.scale)
                } else {
                    return nil
                }
            }
            return result
        }

        mutating func parseFactor() -> UnitSpec? {
            guard index < chars.count else { return nil }
            var base: UnitSpec
            if chars[index] == "(" {
                index += 1
                guard let inner = parseProduct(), index < chars.count, chars[index] == ")" else { return nil }
                index += 1
                base = inner
            } else if chars[index] == "1" {
                index += 1
                base = .one
            } else {
                var symbol = ""
                while index < chars.count, !"·*⋅ /()^".contains(chars[index]), !Self.superscripts.keys.contains(chars[index]) {
                    symbol.append(chars[index]); index += 1
                }
                guard let a = UnitLibrary.atom(symbol) else { return nil }
                base = a
            }
            // Exponent: ^2, ^-1 or superscripts ² ³ ⁻¹
            var expText = ""
            if index < chars.count, chars[index] == "^" {
                index += 1
                while index < chars.count, chars[index] == "-" || chars[index].isNumber { expText.append(chars[index]); index += 1 }
            } else {
                while index < chars.count, let d = Self.superscripts[chars[index]] { expText.append(d); index += 1 }
            }
            if !expText.isEmpty {
                guard let n = Int(expText) else { return nil }
                return UnitSpec(dimension: base.dimension.power(n), scale: pow(base.scale, Double(n)))
            }
            return base
        }

        static let superscripts: [Character: Character] = [
            "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-",
        ]
    }

    // MARK: Conversion

    static func convert(_ value: Double, from: String, to: String) throws -> Double {
        guard let a = parse(from) else { throw CalcError.domain("Unknown unit: \(from)") }
        guard let b = parse(to) else { throw CalcError.domain("Unknown unit: \(to)") }
        guard a.dimension == b.dimension else {
            throw CalcError.domain("Can't convert \(from) to \(to): \(a.dimension.description) vs \(b.dimension.description)")
        }
        let si = value * a.scale + a.offset
        return (si - b.offset) / b.scale
    }
}

// MARK: - Unit checking

/// Dimensional analysis of a formula: infers each result's unit from the
/// declared input units and flags mismatches (e.g. adding metres to seconds,
/// or a result declared in J that actually comes out in N).
struct UnitChecker {
    let engine: CalculatorEngine

    struct Report {
        /// Inferred unit description per output.
        var inferred: [String: String] = [:]
        var warnings: [String] = []
        var isConsistent: Bool { warnings.isEmpty }
    }

    func check(_ formula: Formula) -> Report {
        var report = Report()
        guard let statements = try? engine.parse(formula) else { return report }
        var dims: [String: UnitDimension] = [:]
        // Declared input units.
        for v in formula.variables where !v.unit.isEmpty {
            if let spec = UnitLibrary.parse(v.unit) { dims[v.name] = spec.dimension }
        }
        // Units of dependency outputs.
        func lookup(_ name: String) -> UnitDimension? {
            if let d = dims[name] { return d }
            if let c = Constants.all.first(where: { $0.id == name }) {
                return UnitLibrary.parse(c.unit)?.dimension ?? UnitDimension.none
            }
            if Constants.isConstant(name) { return UnitDimension.none }
            if let dep = engine.formula(producing: name, excluding: formula.id),
               let unit = dep.variable(name)?.unit, let spec = UnitLibrary.parse(unit) {
                return spec.dimension
            }
            if let v = formula.variable(name), v.unit.isEmpty { return UnitDimension.none }
            return nil
        }

        for s in statements {
            var warnings: [String] = []
            let d = dimension(of: s.expression, lookup: lookup, warnings: &warnings)
            report.warnings += warnings.map { w in (s.target.map { "\($0): " } ?? "") + w }
            guard let target = s.target else { continue }
            if let d {
                dims[target] = d
                report.inferred[target] = d.description
                if let declared = formula.variable(target)?.unit, !declared.isEmpty {
                    if let spec = UnitLibrary.parse(declared) {
                        if spec.dimension != d {
                            report.warnings.append("\(target) is declared in \(declared) (\(spec.dimension.description)) but the expression gives \(d.description)")
                        }
                    } else {
                        report.warnings.append("Unknown unit \"\(declared)\" for \(target)")
                    }
                }
            } else if let declared = formula.variable(target)?.unit, let spec = UnitLibrary.parse(declared) {
                dims[target] = spec.dimension
            }
        }
        for v in formula.variables where !v.unit.isEmpty && UnitLibrary.parse(v.unit) == nil {
            if !report.warnings.contains(where: { $0.contains("\"\(v.unit)\"") }) {
                report.warnings.append("Unknown unit \"\(v.unit)\" for \(v.name)")
            }
        }
        return report
    }

    /// UnitDimension of an expression, or nil if it can't be determined.
    private func dimension(of e: Expr, lookup: (String) -> UnitDimension?, warnings: inout [String]) -> UnitDimension? {
        switch e {
        case .number:
            return UnitDimension.none
        case let .variable(n):
            return lookup(n)
        case let .negate(x):
            return dimension(of: x, lookup: lookup, warnings: &warnings)
        case let .postfix(op, x):
            let d = dimension(of: x, lookup: lookup, warnings: &warnings)
            return op == "%" ? d : UnitDimension.none
        case let .binary(op, l, r):
            let a = dimension(of: l, lookup: lookup, warnings: &warnings)
            if op == "^" {
                guard let a else { return nil }
                if a.isDimensionless { return a }
                guard let n = Self.integerLiteral(r) else { return nil }
                return a.power(n)
            }
            let b = dimension(of: r, lookup: lookup, warnings: &warnings)
            guard let a, let b else { return nil }
            switch op {
            case "*": return a * b
            case "/": return a / b
            default:
                if a != b {
                    warnings.append("adding/subtracting \(a.description) and \(b.description)")
                }
                return a
            }
        case let .call(name, args):
            let ds = args.map { dimension(of: $0, lookup: lookup, warnings: &warnings) }
            switch name {
            case "sqrt": return ds.first??.root(2)
            case "cbrt": return ds.first??.root(3)
            case "root":
                guard args.count == 2, let d = ds[0], let n = Self.integerLiteral(args[1]) else { return nil }
                return d.root(n)
            case "abs", "floor", "ceil", "round", "min", "max", "sum", "avg", "hypot", "mod":
                return ds.first ?? nil
            default:
                return UnitDimension.none
            }
        }
    }

    private static func integerLiteral(_ e: Expr) -> Int? {
        switch e {
        case let .number(v) where v == v.rounded(): return Int(v)
        case let .negate(.number(v)) where v == v.rounded(): return -Int(v)
        default: return nil
        }
    }
}
