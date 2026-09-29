#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// Maps a physical (Bluetooth / Smart Keyboard / Mac) keyboard onto the
/// calculator keypad. Press and release are forwarded separately, so held
/// keys behave like held calculator keys.
///
/// Digits, operators, parentheses, "." and "," map to the matching keys;
/// Return = ENTER, Delete = DEL, Escape = CLEAR, arrows = arrow pad,
/// Tab = 2ND, Left Option = ALPHA, F1–F5 = Y=/WINDOW/ZOOM/TRACE/GRAPH,
/// "^" = ^, "~" = (−), "o" = ON.
struct HardwareKeyboardReader: UIViewRepresentable {
    let onPress: (Key) -> Void
    let onRelease: (Key) -> Void

    func makeUIView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onPress = onPress
        view.onRelease = onRelease
        return view
    }

    func updateUIView(_ view: KeyCaptureView, context: Context) {
        view.onPress = onPress
        view.onRelease = onRelease
    }
}

final class KeyCaptureView: UIView {
    var onPress: ((Key) -> Void)?
    var onRelease: ((Key) -> Void)?
    private var active: [UIPress: Key] = [:]

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in self?.becomeFirstResponder() }
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            if let uiKey = press.key, let key = Self.map(uiKey) {
                active[press] = key
                onPress?(key)
                handled = true
            }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        releaseAll(presses)
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        releaseAll(presses)
        super.pressesCancelled(presses, with: event)
    }

    private func releaseAll(_ presses: Set<UIPress>) {
        for press in presses {
            if let key = active.removeValue(forKey: press) { onRelease?(key) }
        }
    }

    static func map(_ key: UIKey) -> Key? {
        switch key.keyCode {
        case .keyboardUpArrow: return .up
        case .keyboardDownArrow: return .down
        case .keyboardLeftArrow: return .left
        case .keyboardRightArrow: return .right
        case .keyboardReturnOrEnter, .keypadEnter: return .enter
        case .keyboardDeleteOrBackspace, .keyboardDeleteForward: return .delete
        case .keyboardEscape: return .clear
        case .keyboardTab: return .second
        case .keyboardLeftAlt: return .alpha
        case .keyboardF1: return .yEquals
        case .keyboardF2: return .window
        case .keyboardF3: return .zoom
        case .keyboardF4: return .trace
        case .keyboardF5: return .graph
        default: break
        }
        switch key.characters {
        case "0": return .zero
        case "1": return .one
        case "2": return .two
        case "3": return .three
        case "4": return .four
        case "5": return .five
        case "6": return .six
        case "7": return .seven
        case "8": return .eight
        case "9": return .nine
        case ".": return .decimal
        case ",": return .comma
        case "+": return .add
        case "-": return .subtract
        case "*": return .multiply
        case "/": return .divide
        case "^": return .power
        case "(": return .leftParen
        case ")": return .rightParen
        case "~": return .negate
        case "o", "O": return .on
        default: return nil
        }
    }
}
#endif
