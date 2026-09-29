/// A physical key on the TI-84 Plus keypad, identified by its position in
/// the hardware key matrix (group = port 01h select line, bit = data line).
/// ON is not part of the matrix; it is wired to the interrupt controller.
public enum Key: String, CaseIterable, Codable, Hashable, Sendable {
    // Group 0
    case down, left, right, up
    // Group 1
    case enter, add, subtract, multiply, divide, power, clear
    // Group 2
    case negate, three, six, nine, rightParen, tan, vars
    // Group 3
    case decimal, two, five, eight, leftParen, cos, prgm, stat
    // Group 4
    case zero, one, four, seven, comma, sin, apps, xtThetaN
    // Group 5
    case store, ln, log, square, inverse, math, alpha
    // Group 6
    case graph, trace, zoom, window, yEquals, second, mode, delete
    // Not in the matrix
    case on

    /// (group, bit) in the key matrix; nil for ON.
    public var matrixPosition: (group: Int, bit: Int)? {
        switch self {
        case .down: return (0, 0)
        case .left: return (0, 1)
        case .right: return (0, 2)
        case .up: return (0, 3)
        case .enter: return (1, 0)
        case .add: return (1, 1)
        case .subtract: return (1, 2)
        case .multiply: return (1, 3)
        case .divide: return (1, 4)
        case .power: return (1, 5)
        case .clear: return (1, 6)
        case .negate: return (2, 0)
        case .three: return (2, 1)
        case .six: return (2, 2)
        case .nine: return (2, 3)
        case .rightParen: return (2, 4)
        case .tan: return (2, 5)
        case .vars: return (2, 6)
        case .decimal: return (3, 0)
        case .two: return (3, 1)
        case .five: return (3, 2)
        case .eight: return (3, 3)
        case .leftParen: return (3, 4)
        case .cos: return (3, 5)
        case .prgm: return (3, 6)
        case .stat: return (3, 7)
        case .zero: return (4, 0)
        case .one: return (4, 1)
        case .four: return (4, 2)
        case .seven: return (4, 3)
        case .comma: return (4, 4)
        case .sin: return (4, 5)
        case .apps: return (4, 6)
        case .xtThetaN: return (4, 7)
        case .store: return (5, 1)
        case .ln: return (5, 2)
        case .log: return (5, 3)
        case .square: return (5, 4)
        case .inverse: return (5, 5)
        case .math: return (5, 6)
        case .alpha: return (5, 7)
        case .graph: return (6, 0)
        case .trace: return (6, 1)
        case .zoom: return (6, 2)
        case .window: return (6, 3)
        case .yEquals: return (6, 4)
        case .second: return (6, 5)
        case .mode: return (6, 6)
        case .delete: return (6, 7)
        case .on: return nil
        }
    }

    /// TI-OS scan code (as returned by _GetCSC), useful for debugging.
    public var scanCode: UInt8? {
        guard let p = matrixPosition else { return nil }
        return UInt8(p.group * 8 + p.bit + 1)
    }
}

/// The keypad matrix behind port 01h.
///
/// The CPU writes a mask to port 01h: each 0 bit drives one key group
/// (row) low. Reading port 01h returns the data lines, where a 0 bit means a
/// key in any selected group is pressed at that position. Pressing several
/// keys can create "ghost" connections between groups, which the matrix
/// reproduces.
public final class KeyboardMatrix: IODevice {
    public private(set) var groupMask: UInt8 = 0xFF
    /// Pressed keys: one byte per group, bit set = pressed.
    public private(set) var pressedByGroup = [UInt8](repeating: 0, count: 8)
    public private(set) var onKeyDown = false

    /// ON press/release edges go to the interrupt controller.
    var onKeyChanged: ((Bool) -> Void)?

    public init() {}

    public func reset() {
        groupMask = 0xFF
    }

    public func setKey(_ key: Key, pressed: Bool) {
        if let (group, bit) = key.matrixPosition {
            if pressed {
                pressedByGroup[group] |= 1 << UInt8(bit)
            } else {
                pressedByGroup[group] &= ~(1 << UInt8(bit))
            }
        } else if onKeyDown != pressed {
            onKeyDown = pressed
            onKeyChanged?(pressed)
        }
    }

    public func releaseAll() {
        pressedByGroup = [UInt8](repeating: 0, count: 8)
        if onKeyDown { setKey(.on, pressed: false) }
    }

    public func isPressed(_ key: Key) -> Bool {
        guard let (group, bit) = key.matrixPosition else { return onKeyDown }
        return pressedByGroup[group] & (1 << UInt8(bit)) != 0
    }

    public var pressedKeys: [Key] { Key.allCases.filter(isPressed) }

    /// Data lines seen with the current group mask (active low).
    public var scan: UInt8 {
        var lines: UInt8 = 0
        for group in 0..<8 where groupMask & (1 << UInt8(group)) == 0 {
            lines |= pressedByGroup[group]
        }
        // Ghosting: a pressed key connects its group to its data line, so
        // any group sharing a pressed column with the active set joins in.
        var previous: UInt8
        repeat {
            previous = lines
            for group in 0..<8 where pressedByGroup[group] & lines != 0 {
                lines |= pressedByGroup[group]
            }
        } while lines != previous
        return ~lines
    }

    // MARK: IODevice (port 01h)

    public func read(port: UInt8) -> UInt8 { scan }

    public func write(port: UInt8, value: UInt8) { groupMask = value }

    var snapshot: KeyboardState { KeyboardState(groupMask: groupMask) }
    func restore(_ s: KeyboardState) { groupMask = s.groupMask }
}

public struct KeyboardState: Codable, Equatable, Sendable {
    var groupMask: UInt8
}
