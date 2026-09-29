#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import TI84EmulatorCore

/// Visual style of a key cap, following the TI-84 Plus colour scheme.
enum KeyStyle {
    case function     // dark keys (Y=, MATH, SIN, ...)
    case number       // light gray number pad
    case operation    // right-hand column (÷ × − + ENTER)
    case second       // blue 2ND
    case alpha        // green ALPHA
    case arrow        // direction pad

    var fill: Color {
        switch self {
        case .function: return Color(red: 0.16, green: 0.17, blue: 0.20)
        case .number: return Color(red: 0.86, green: 0.87, blue: 0.89)
        case .operation: return Color(red: 0.30, green: 0.32, blue: 0.36)
        case .second: return Color(red: 0.33, green: 0.62, blue: 0.87)
        case .alpha: return Color(red: 0.36, green: 0.70, blue: 0.40)
        case .arrow: return Color(red: 0.55, green: 0.57, blue: 0.61)
        }
    }

    var label: Color {
        switch self {
        case .number: return Color(red: 0.08, green: 0.09, blue: 0.12)
        case .second, .alpha: return .white
        default: return .white
        }
    }
}

/// Printed legends around a key: the key's own function, the 2ND function
/// (blue, above left) and the ALPHA character (green, above right).
struct KeyDefinition: Identifiable {
    let key: Key
    let label: String
    var second: String = ""
    var alpha: String = ""
    var style: KeyStyle = .function

    var id: Key { key }
}

/// The TI-84 Plus keypad, row by row. Pressing a key only changes the
/// emulated key matrix; what the key does is decided by the ROM.
enum KeyLayout {
    static let graphRow: [KeyDefinition] = [
        .init(key: .yEquals, label: "Y=", second: "STAT PLOT", alpha: "F1"),
        .init(key: .window, label: "WINDOW", second: "TBLSET", alpha: "F2"),
        .init(key: .zoom, label: "ZOOM", second: "FORMAT", alpha: "F3"),
        .init(key: .trace, label: "TRACE", second: "CALC", alpha: "F4"),
        .init(key: .graph, label: "GRAPH", second: "TABLE", alpha: "F5"),
    ]

    /// Rows 2 and 3 have three keys on the left and the arrow pad on the right.
    static let upperLeft: [[KeyDefinition]] = [
        [
            .init(key: .second, label: "2ND", style: .second),
            .init(key: .mode, label: "MODE", second: "QUIT"),
            .init(key: .delete, label: "DEL", second: "INS"),
        ],
        [
            .init(key: .alpha, label: "ALPHA", second: "A-LOCK", style: .alpha),
            .init(key: .xtThetaN, label: "X,T,θ,n", second: "LINK"),
            .init(key: .stat, label: "STAT", second: "LIST"),
        ],
    ]

    static let mainRows: [[KeyDefinition]] = [
        [
            .init(key: .math, label: "MATH", second: "TEST", alpha: "A"),
            .init(key: .apps, label: "APPS", second: "ANGLE", alpha: "B"),
            .init(key: .prgm, label: "PRGM", second: "DRAW", alpha: "C"),
            .init(key: .vars, label: "VARS", second: "DISTR"),
            .init(key: .clear, label: "CLEAR"),
        ],
        [
            .init(key: .inverse, label: "x⁻¹", second: "MATRIX", alpha: "D"),
            .init(key: .sin, label: "SIN", second: "SIN⁻¹", alpha: "E"),
            .init(key: .cos, label: "COS", second: "COS⁻¹", alpha: "F"),
            .init(key: .tan, label: "TAN", second: "TAN⁻¹", alpha: "G"),
            .init(key: .power, label: "^", second: "π", alpha: "H", style: .operation),
        ],
        [
            .init(key: .square, label: "x²", second: "√", alpha: "I"),
            .init(key: .comma, label: ",", second: "EE", alpha: "J"),
            .init(key: .leftParen, label: "(", second: "{", alpha: "K"),
            .init(key: .rightParen, label: ")", second: "}", alpha: "L"),
            .init(key: .divide, label: "÷", second: "e", alpha: "M", style: .operation),
        ],
        [
            .init(key: .log, label: "LOG", second: "10ˣ", alpha: "N"),
            .init(key: .seven, label: "7", second: "u", alpha: "O", style: .number),
            .init(key: .eight, label: "8", second: "v", alpha: "P", style: .number),
            .init(key: .nine, label: "9", second: "w", alpha: "Q", style: .number),
            .init(key: .multiply, label: "×", second: "[", alpha: "R", style: .operation),
        ],
        [
            .init(key: .ln, label: "LN", second: "eˣ", alpha: "S"),
            .init(key: .four, label: "4", second: "L4", alpha: "T", style: .number),
            .init(key: .five, label: "5", second: "L5", alpha: "U", style: .number),
            .init(key: .six, label: "6", second: "L6", alpha: "V", style: .number),
            .init(key: .subtract, label: "−", second: "]", alpha: "W", style: .operation),
        ],
        [
            .init(key: .store, label: "STO→", second: "RCL", alpha: "X"),
            .init(key: .one, label: "1", second: "L1", alpha: "Y", style: .number),
            .init(key: .two, label: "2", second: "L2", alpha: "Z", style: .number),
            .init(key: .three, label: "3", second: "L3", alpha: "θ", style: .number),
            .init(key: .add, label: "+", second: "MEM", alpha: "\"", style: .operation),
        ],
        [
            .init(key: .on, label: "ON", second: "OFF"),
            .init(key: .zero, label: "0", second: "CATALOG", alpha: "␣", style: .number),
            .init(key: .decimal, label: ".", second: "i", alpha: ":", style: .number),
            .init(key: .negate, label: "(−)", second: "ANS", alpha: "?", style: .number),
            .init(key: .enter, label: "ENTER", second: "ENTRY", alpha: "SOLVE", style: .operation),
        ],
    ]
}
#endif
