import Foundation

/// The formula library that ships with Basis. Built-ins are read-only (they
/// can be duplicated and edited) and have stable ids so history entries keep
/// pointing at them across updates.
enum BuiltInFormulas {
    private static func v(_ name: String, _ label: String, _ unit: String = "", _ defaultValue: String = "") -> FormulaVariable {
        FormulaVariable(name: name, label: label, unit: unit, defaultValue: defaultValue)
    }

    private static func make(_ n: Int, _ name: String, _ category: String, _ summary: String, _ expression: String,
                             _ variables: [FormulaVariable], exports: Bool = false) -> Formula {
        Formula(id: UUID(uuidString: String(format: "B0A51500-0000-4000-8000-%012ld", n))!,
                name: name, category: category, summary: summary, expression: expression,
                variables: variables, isBuiltIn: true, exportsOutputs: exports)
    }

    static let categories = ["Math", "Physics", "Engineering", "Electrical"]

    static let all: [Formula] = [
        // Math
        make(1, "Quadratic Formula", "Math", "Roots of ax² + bx + c = 0",
             "x₁ = (-b + √(b² - 4ac)) / (2a)\nx₂ = (-b - √(b² - 4ac)) / (2a)",
             [v("a", "coefficient of x²"), v("b", "coefficient of x"), v("c", "constant term")]),
        make(2, "Pythagorean Theorem", "Math", "Hypotenuse of a right triangle",
             "c = √(a² + b²)", [v("a", "leg"), v("b", "leg"), v("c", "hypotenuse")]),
        make(3, "Distance Formula", "Math", "Distance between two points",
             "d = √((x₂ - x₁)² + (y₂ - y₁)²)", [v("x₁", "x of point 1"), v("y₁", "y of point 1"), v("x₂", "x of point 2"), v("y₂", "y of point 2")]),
        make(4, "Slope", "Math", "Slope of the line through two points",
             "m = (y₂ - y₁) / (x₂ - x₁)", [v("x₁", "x of point 1"), v("y₁", "y of point 1"), v("x₂", "x of point 2"), v("y₂", "y of point 2")]),
        make(5, "Circle Area", "Math", "A = πr²", "A = π r²", [v("r", "radius", "m"), v("A", "area", "m²")]),
        make(6, "Circle Circumference", "Math", "C = 2πr", "C = 2π r", [v("r", "radius", "m"), v("C", "circumference", "m")]),
        make(7, "Sphere Volume", "Math", "V = 4/3 πr³", "V = 4/3 π r³", [v("r", "radius", "m"), v("V", "volume", "m³")]),
        make(8, "Law of Cosines", "Math", "Third side from two sides and the included angle",
             "c = √(a² + b² - 2ab cos(γ))", [v("a", "side"), v("b", "side"), v("γ", "included angle"), v("c", "opposite side")]),

        // Physics
        make(20, "Kinetic Energy", "Physics", "KE = ½mv²", "KE = ½ m v²",
             [v("m", "mass", "kg"), v("v", "velocity", "m/s"), v("KE", "kinetic energy", "J")], exports: true),
        make(21, "Potential Energy", "Physics", "Gravitational potential energy, PE = mgh", "PE = m g h",
             [v("m", "mass", "kg"), v("g", "gravitational acceleration", "m/s²", "9.80665"), v("h", "height", "m"),
              v("PE", "potential energy", "J")], exports: true),
        make(22, "Mechanical Energy", "Physics", "Uses the Kinetic and Potential Energy formulas", "E = KE + PE",
             [v("E", "total mechanical energy", "J")]),
        make(23, "Momentum", "Physics", "p = mv", "p = m v", [v("m", "mass", "kg"), v("v", "velocity", "m/s"), v("p", "momentum", "kg·m/s")]),
        make(24, "Newton's Second Law", "Physics", "F = ma", "F = m a", [v("m", "mass", "kg"), v("a", "acceleration", "m/s²"), v("F", "net force", "N")]),
        make(25, "Work", "Physics", "Work done by a constant force", "W = F d cos(θ)",
             [v("F", "force", "N"), v("d", "displacement", "m"), v("θ", "angle between force and motion", "", "0"), v("W", "work", "J")]),
        make(26, "Power", "Physics", "P = W/t", "P = W / t", [v("W", "work", "J"), v("t", "time", "s"), v("P", "power", "W")]),
        make(27, "Projectile Motion", "Physics", "Launch from level ground (no air resistance)",
             "vx = v0 cos(θ)\nvy = v0 sin(θ)\nt_flight = 2 vy / g\nR = vx t_flight\nH = vy² / (2g)",
             [v("v0", "launch speed", "m/s"), v("θ", "launch angle"), v("g", "gravitational acceleration", "m/s²", "9.80665"),
              v("vx", "horizontal velocity", "m/s"), v("vy", "initial vertical velocity", "m/s"),
              v("t_flight", "time of flight", "s"), v("R", "range", "m"), v("H", "maximum height", "m")]),
        make(28, "Constant Acceleration", "Physics", "Velocity and displacement after time t",
             "v = v0 + a t\ns = v0 t + ½ a t²",
             [v("v0", "initial velocity", "m/s"), v("a", "acceleration", "m/s²"), v("t", "time", "s"),
              v("v", "final velocity", "m/s"), v("s", "displacement", "m")]),
        make(29, "Hooke's Law", "Physics", "Spring force F = kx", "F = k x",
             [v("k", "spring constant", "N/m"), v("x", "extension", "m"), v("F", "force", "N")]),

        // Engineering
        make(40, "Stress", "Engineering", "Normal stress σ = F/A", "σ = F / A",
             [v("F", "axial force", "N"), v("A", "cross-sectional area", "m²"), v("σ", "stress", "Pa")]),
        make(41, "Strain", "Engineering", "Normal strain ε = ΔL/L₀", "ε = ΔL / L0",
             [v("ΔL", "change in length", "m"), v("L0", "original length", "m"), v("ε", "strain")]),
        make(42, "Young's Modulus", "Engineering", "E = σ/ε", "E = σ / ε",
             [v("σ", "stress", "Pa"), v("ε", "strain"), v("E", "modulus of elasticity", "Pa")]),
        make(43, "Torque", "Engineering", "τ = rF sin θ", "τ = r F sin(θ)",
             [v("r", "lever arm", "m"), v("F", "force", "N"), v("θ", "angle between r and F", "", "90°"), v("τ", "torque", "N·m")]),
        make(44, "Cantilever Beam (End Load)", "Engineering", "Tip deflection and fixed-end moment",
             "δ = F L³ / (3 E I)\nM = F L",
             [v("F", "end load", "N"), v("L", "length", "m"), v("E", "modulus of elasticity", "Pa"), v("I", "second moment of area", "m⁴"),
              v("δ", "tip deflection", "m"), v("M", "maximum moment", "N·m")]),
        make(45, "Simply Supported Beam (Center Load)", "Engineering", "Midspan deflection and maximum moment",
             "δ = F L³ / (48 E I)\nM = F L / 4",
             [v("F", "center load", "N"), v("L", "span", "m"), v("E", "modulus of elasticity", "Pa"), v("I", "second moment of area", "m⁴"),
              v("δ", "midspan deflection", "m"), v("M", "maximum moment", "N·m")]),
        make(46, "Rectangular Section Inertia", "Engineering", "I = bh³/12", "I = b h³ / 12",
             [v("b", "width", "m"), v("h", "height", "m"), v("I", "second moment of area", "m⁴")]),
        make(47, "Ideal Gas Law", "Engineering", "Pressure from PV = nRT", "P = n R_u T / V",
             [v("n", "amount of gas", "mol"), v("T", "temperature", "K"), v("V", "volume", "m³"), v("P", "pressure", "Pa")]),

        // Electrical
        make(60, "Ohm's Law", "Electrical", "V = IR", "V = I R", [v("I", "current", "A"), v("R", "resistance", "Ω"), v("V", "voltage", "V")]),
        make(61, "Electrical Power", "Electrical", "P = VI", "P = V I", [v("V", "voltage", "V"), v("I", "current", "A"), v("P", "power", "W")]),
        make(62, "Series Resistance", "Electrical", "R = R₁ + R₂ + R₃", "R_eq = R₁ + R₂ + R₃",
             [v("R₁", "resistor 1", "Ω"), v("R₂", "resistor 2", "Ω"), v("R₃", "resistor 3", "Ω", "0"), v("R_eq", "equivalent resistance", "Ω")]),
        make(63, "Parallel Resistance", "Electrical", "1/R = 1/R₁ + 1/R₂", "R_eq = 1 / (1/R₁ + 1/R₂)",
             [v("R₁", "resistor 1", "Ω"), v("R₂", "resistor 2", "Ω"), v("R_eq", "equivalent resistance", "Ω")]),
        make(64, "RC Time Constant", "Electrical", "τ = RC", "τ = R C", [v("R", "resistance", "Ω"), v("C", "capacitance", "F"), v("τ", "time constant", "s")]),
    ]
}
