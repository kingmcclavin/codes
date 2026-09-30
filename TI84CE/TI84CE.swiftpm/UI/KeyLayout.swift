import SwiftUI

/// Visual style of a key cap.
enum KeyStyle {
    case graphRow       // top row: y=, window, zoom, trace, graph
    case second         // blue 2nd key
    case alpha          // green alpha key
    case function       // dark function keys (math, sin, ...)
    case number         // light number keys
    case enter
    case arrow
    case on

    var capColor: Color {
        switch self {
        case .graphRow: return Color(red: 0.80, green: 0.81, blue: 0.83)
        case .second: return Color(red: 0.22, green: 0.55, blue: 0.86)
        case .alpha: return Color(red: 0.36, green: 0.68, blue: 0.27)
        case .function, .on: return Color(red: 0.16, green: 0.16, blue: 0.17)
        case .number: return Color(red: 0.93, green: 0.93, blue: 0.94)
        case .enter: return Color(red: 0.78, green: 0.79, blue: 0.81)
        case .arrow: return Color(red: 0.30, green: 0.31, blue: 0.33)
        }
    }

    var textColor: Color {
        switch self {
        case .graphRow, .number, .enter: return Color(white: 0.08)
        default: return .white
        }
    }
}

/// One physical key: the matrix key it drives plus the legends printed on and
/// above it. The legends are labels only; the ROM decides what each key does.
struct KeyDefinition: Identifiable {
    let key: CalculatorKey
    let label: String
    var second: String? = nil
    var alpha: String? = nil
    let style: KeyStyle
    var id: CalculatorKey { key }
}

enum KeyLayout {
    static let graphRow: [KeyDefinition] = [
        .init(key: .yEquals, label: "y=", second: "stat plot", alpha: "f1", style: .graphRow),
        .init(key: .window, label: "window", second: "tblset", alpha: "f2", style: .graphRow),
        .init(key: .zoom, label: "zoom", second: "format", alpha: "f3", style: .graphRow),
        .init(key: .trace, label: "trace", second: "calc", alpha: "f4", style: .graphRow),
        .init(key: .graph, label: "graph", second: "table", alpha: "f5", style: .graphRow),
    ]

    /// Left block beside the arrow pad (2 rows x 3 keys).
    static let controlRows: [[KeyDefinition]] = [
        [
            .init(key: .second, label: "2nd", style: .second),
            .init(key: .mode, label: "mode", second: "quit", style: .function),
            .init(key: .del, label: "del", second: "ins", style: .function),
        ],
        [
            .init(key: .alpha, label: "alpha", second: "A-lock", style: .alpha),
            .init(key: .xton, label: "X,T,θ,n", second: "link", style: .function),
            .init(key: .stat, label: "stat", second: "list", style: .function),
        ],
    ]

    static let mainRows: [[KeyDefinition]] = [
        [
            .init(key: .math, label: "math", second: "test", alpha: "A", style: .function),
            .init(key: .apps, label: "apps", second: "angle", alpha: "B", style: .function),
            .init(key: .prgm, label: "prgm", second: "draw", alpha: "C", style: .function),
            .init(key: .vars, label: "vars", second: "distr", style: .function),
            .init(key: .clear, label: "clear", style: .function),
        ],
        [
            .init(key: .inverse, label: "x⁻¹", second: "matrix", alpha: "D", style: .function),
            .init(key: .sin, label: "sin", second: "sin⁻¹", alpha: "E", style: .function),
            .init(key: .cos, label: "cos", second: "cos⁻¹", alpha: "F", style: .function),
            .init(key: .tan, label: "tan", second: "tan⁻¹", alpha: "G", style: .function),
            .init(key: .power, label: "^", second: "π", alpha: "H", style: .function),
        ],
        [
            .init(key: .square, label: "x²", second: "√", alpha: "I", style: .function),
            .init(key: .comma, label: ",", second: "EE", alpha: "J", style: .function),
            .init(key: .leftParen, label: "(", second: "{", alpha: "K", style: .function),
            .init(key: .rightParen, label: ")", second: "}", alpha: "L", style: .function),
            .init(key: .divide, label: "÷", second: "e", alpha: "M", style: .function),
        ],
        [
            .init(key: .log, label: "log", second: "10ˣ", alpha: "N", style: .function),
            .init(key: .k7, label: "7", second: "u", alpha: "O", style: .number),
            .init(key: .k8, label: "8", second: "v", alpha: "P", style: .number),
            .init(key: .k9, label: "9", second: "w", alpha: "Q", style: .number),
            .init(key: .multiply, label: "×", second: "[", alpha: "R", style: .function),
        ],
        [
            .init(key: .ln, label: "ln", second: "eˣ", alpha: "S", style: .function),
            .init(key: .k4, label: "4", second: "L4", alpha: "T", style: .number),
            .init(key: .k5, label: "5", second: "L5", alpha: "U", style: .number),
            .init(key: .k6, label: "6", second: "L6", alpha: "V", style: .number),
            .init(key: .subtract, label: "−", second: "]", alpha: "W", style: .function),
        ],
        [
            .init(key: .sto, label: "sto→", second: "rcl", alpha: "X", style: .function),
            .init(key: .k1, label: "1", second: "L1", alpha: "Y", style: .number),
            .init(key: .k2, label: "2", second: "L2", alpha: "Z", style: .number),
            .init(key: .k3, label: "3", second: "L3", alpha: "θ", style: .number),
            .init(key: .add, label: "+", second: "mem", alpha: "\"", style: .function),
        ],
        [
            .init(key: .on, label: "on", second: "off", style: .on),
            .init(key: .k0, label: "0", second: "catalog", alpha: "␣", style: .number),
            .init(key: .decimal, label: ".", second: "i", alpha: ":", style: .number),
            .init(key: .negate, label: "(−)", second: "ans", alpha: "?", style: .number),
            .init(key: .enter, label: "enter", second: "entry", alpha: "solve", style: .enter),
        ],
    ]
}
