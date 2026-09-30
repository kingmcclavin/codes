import SwiftUI
import UIKit

/// Maps a hardware keyboard (iPad Magic Keyboard, Bluetooth keyboard, Mac) to
/// calculator keys with true key-down / key-up events, so holding a key on the
/// keyboard holds it on the calculator.
enum HardwareKeyMap {
    static func key(for usage: UIKeyboardHIDUsage) -> CalculatorKey? {
        switch usage {
        case .keyboard0: return .k0
        case .keyboard1: return .k1
        case .keyboard2: return .k2
        case .keyboard3: return .k3
        case .keyboard4: return .k4
        case .keyboard5: return .k5
        case .keyboard6: return .k6
        case .keyboard7: return .k7
        case .keyboard8: return .k8
        case .keyboard9: return .k9
        case .keypad0: return .k0
        case .keypad1: return .k1
        case .keypad2: return .k2
        case .keypad3: return .k3
        case .keypad4: return .k4
        case .keypad5: return .k5
        case .keypad6: return .k6
        case .keypad7: return .k7
        case .keypad8: return .k8
        case .keypad9: return .k9
        case .keyboardPeriod, .keypadPeriod: return .decimal
        case .keyboardComma: return .comma
        case .keyboardHyphen, .keypadHyphen: return .subtract
        case .keypadPlus: return .add
        case .keypadAsterisk: return .multiply
        case .keyboardSlash, .keypadSlash: return .divide
        case .keyboardReturnOrEnter, .keypadEnter: return .enter
        case .keyboardDeleteOrBackspace: return .del
        case .keyboardEscape: return .clear
        case .keyboardUpArrow: return .up
        case .keyboardDownArrow: return .down
        case .keyboardLeftArrow: return .left
        case .keyboardRightArrow: return .right
        case .keyboardTab: return .second
        case .keyboardLeftAlt, .keyboardRightAlt: return .alpha
        case .keyboardOpenBracket: return .leftParen
        case .keyboardCloseBracket: return .rightParen
        case .keyboardEqualSign: return .add
        case .keyboardGraveAccentAndTilde: return .negate
        case .keyboardF1: return .yEquals
        case .keyboardF2: return .window
        case .keyboardF3: return .zoom
        case .keyboardF4: return .trace
        case .keyboardF5: return .graph
        case .keyboardF6: return .on
        case .keyboardM: return .math
        case .keyboardA: return .apps
        case .keyboardP: return .prgm
        case .keyboardV: return .vars
        case .keyboardS: return .sin
        case .keyboardC: return .cos
        case .keyboardT: return .tan
        case .keyboardL: return .log
        case .keyboardN: return .ln
        case .keyboardX: return .xton
        case .keyboardI: return .inverse
        case .keyboardQ: return .square
        case .keyboardK: return .sto
        case .keyboardD: return .mode
        case .keyboardE: return .stat
        case .keyboardH: return .power
        default: return nil
        }
    }

    /// Legend for the settings screen.
    static let help: [(String, String)] = [
        ("0-9 . , + − × ÷", "Digits and operators"),
        ("Return", "enter"),
        ("Delete", "del"),
        ("Esc", "clear"),
        ("Tab", "2nd"),
        ("Option", "alpha"),
        ("Arrow keys", "Arrow pad"),
        ("F1…F5", "y=, window, zoom, trace, graph"),
        ("F6", "on"),
        ("[ ]", "( )"),
        ("`", "(−)"),
        ("H", "^"),
        ("M A P V", "math, apps, prgm, vars"),
        ("S C T", "sin, cos, tan"),
        ("L N", "log, ln"),
        ("X", "X,T,θ,n"),
        ("I Q", "x⁻¹, x²"),
        ("K", "sto→"),
        ("D E", "mode, stat"),
    ]
}

/// An invisible first-responder view that receives hardware key presses.
struct HardwareKeyboardCapture: UIViewRepresentable {
    let onPress: (CalculatorKey) -> Void
    let onRelease: (CalculatorKey) -> Void

    func makeUIView(context: Context) -> KeyCaptureView {
        let v = KeyCaptureView()
        v.onPress = onPress
        v.onRelease = onRelease
        return v
    }

    func updateUIView(_ view: KeyCaptureView, context: Context) {
        view.onPress = onPress
        view.onRelease = onRelease
    }
}

final class KeyCaptureView: UIView {
    var onPress: ((CalculatorKey) -> Void)?
    var onRelease: ((CalculatorKey) -> Void)?
    private var down: [UIKeyboardHIDUsage: CalculatorKey] = [:]

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in _ = self?.becomeFirstResponder() }
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let hid = press.key?.keyCode else { continue }
            // Shift+8 / Shift+= / Shift+6 / Shift+9 / Shift+0 on a US layout.
            let key = shifted(press) ?? HardwareKeyMap.key(for: hid)
            if let key, down[hid] == nil {
                down[hid] = key
                onPress?(key)
                handled = true
            }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        releaseKeys(presses)
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        releaseKeys(presses)
        super.pressesCancelled(presses, with: event)
    }

    private func releaseKeys(_ presses: Set<UIPress>) {
        for press in presses {
            guard let hid = press.key?.keyCode, let key = down.removeValue(forKey: hid) else { continue }
            onRelease?(key)
        }
    }

    private func shifted(_ press: UIPress) -> CalculatorKey? {
        guard let k = press.key, k.modifierFlags.contains(.shift) else { return nil }
        switch k.charactersIgnoringModifiers {
        case "8": return .multiply
        case "=": return .add
        case "6": return .power
        case "9": return .leftParen
        case "0": return .rightParen
        default: return nil
        }
    }
}
