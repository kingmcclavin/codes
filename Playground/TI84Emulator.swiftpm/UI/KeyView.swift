#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// One calculator key with its legends.
///
/// Touch-down presses the key in the emulated matrix and touch-up releases
/// it, so holding a key behaves like the hardware (the OS handles
/// auto-repeat). Several keys can be held at once with multiple fingers.
struct KeyView: View {
    let definition: KeyDefinition
    let width: CGFloat
    let onPress: (Key) -> Void
    let onRelease: (Key) -> Void
    var haptics = true

    @GestureState private var isPressed = false

    private var capHeight: CGFloat { width * 0.52 }
    private var legendFont: Font { .system(size: max(7, width * 0.13), weight: .semibold) }
    private var labelFont: Font {
        let length = definition.label.count
        let factor: CGFloat = length <= 2 ? 0.30 : length <= 4 ? 0.21 : 0.16
        return .system(size: width * factor, weight: .bold, design: .rounded)
    }

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 2) {
                Text(definition.second)
                    .foregroundColor(Color(red: 0.42, green: 0.70, blue: 0.95))
                Spacer(minLength: 0)
                Text(definition.alpha)
                    .foregroundColor(Color(red: 0.45, green: 0.82, blue: 0.48))
            }
            .font(legendFont)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(height: width * 0.17)

            Text(definition.label)
                .font(labelFont)
                .foregroundColor(definition.style.label)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: width, height: capHeight)
                .background(
                    RoundedRectangle(cornerRadius: capHeight * 0.32, style: .continuous)
                        .fill(definition.style.fill)
                        .brightness(isPressed ? -0.18 : 0)
                        .shadow(color: .black.opacity(isPressed ? 0.1 : 0.45), radius: isPressed ? 0.5 : 1.5,
                                y: isPressed ? 0.5 : 1.5)
                )
                .scaleEffect(isPressed ? 0.96 : 1)
                .hoverEffect(.highlight)
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
        )
        .onChange(of: isPressed) { pressed in
            if pressed {
                if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                onPress(definition.key)
            } else {
                onRelease(definition.key)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(definition.label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onPress(definition.key)
            onRelease(definition.key)
        }
    }
}

/// The four-way direction pad.
struct ArrowPad: View {
    let size: CGFloat
    let onPress: (Key) -> Void
    let onRelease: (Key) -> Void
    var haptics = true

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.22))
                .frame(width: size, height: size)
            VStack(spacing: size * 0.18) {
                arrow(.up, "arrowtriangle.up.fill")
                HStack(spacing: size * 0.30) {
                    arrow(.left, "arrowtriangle.left.fill")
                    arrow(.right, "arrowtriangle.right.fill")
                }
                arrow(.down, "arrowtriangle.down.fill")
            }
        }
        .frame(width: size, height: size)
    }

    private func arrow(_ key: Key, _ symbol: String) -> some View {
        ArrowButton(key: key, symbol: symbol, size: size * 0.23, onPress: onPress, onRelease: onRelease,
                    haptics: haptics)
    }
}

private struct ArrowButton: View {
    let key: Key
    let symbol: String
    let size: CGFloat
    let onPress: (Key) -> Void
    let onRelease: (Key) -> Void
    let haptics: Bool

    @GestureState private var isPressed = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.6))
            .foregroundColor(.white)
            .frame(width: size * 1.3, height: size * 1.3)
            .background(Circle().fill(KeyStyle.arrow.fill).brightness(isPressed ? -0.2 : 0))
            .contentShape(Circle())
            .hoverEffect(.highlight)
            .gesture(DragGesture(minimumDistance: 0).updating($isPressed) { _, state, _ in state = true })
            .onChange(of: isPressed) { pressed in
                if pressed {
                    if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                    onPress(key)
                } else {
                    onRelease(key)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(key.rawValue)
            .accessibilityAddTraits(.isButton)
    }
}
#endif
