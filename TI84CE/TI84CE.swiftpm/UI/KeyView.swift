import SwiftUI

/// A single calculator key. Touch-down presses the key in the emulated matrix and
/// lifting the finger (or Pencil) releases it, so the ROM sees real press/hold/
/// release timing, including held keys, auto-repeat and multi-key chords.
struct KeyView: View {
    let definition: KeyDefinition
    let width: CGFloat
    let capHeight: CGFloat
    let onPress: (CalculatorKey) -> Void
    let onRelease: (CalculatorKey) -> Void

    @State private var isPressed = false
    @State private var isHovered = false

    private var legendSize: CGFloat { max(7, capHeight * 0.26) }

    var body: some View {
        VStack(spacing: capHeight * 0.06) {
            legends
            cap
        }
        .frame(width: width)
    }

    private var legends: some View {
        HStack(spacing: 2) {
            Text(definition.second ?? " ")
                .foregroundColor(Color(red: 0.45, green: 0.72, blue: 1.0))
            Spacer(minLength: 0)
            Text(definition.alpha ?? "")
                .foregroundColor(Color(red: 0.55, green: 0.85, blue: 0.40))
        }
        .font(.system(size: legendSize, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(height: legendSize * 1.2)
    }

    private var cap: some View {
        RoundedRectangle(cornerRadius: capHeight * 0.32, style: .continuous)
            .fill(definition.style.capColor)
            .overlay(
                RoundedRectangle(cornerRadius: capHeight * 0.32, style: .continuous)
                    .stroke(Color.white.opacity(isHovered ? 0.55 : 0.12), lineWidth: isHovered ? 1.5 : 0.8)
            )
            .overlay(
                Text(definition.label)
                    .font(.system(size: capHeight * (definition.label.count > 4 ? 0.34 : 0.44), weight: .semibold, design: .rounded))
                    .foregroundColor(definition.style.textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 3)
            )
            .shadow(color: .black.opacity(isPressed ? 0 : 0.5), radius: 0, x: 0, y: isPressed ? 0 : 2)
            .brightness(isPressed ? -0.18 : 0)
            .scaleEffect(isPressed ? 0.95 : 1)
            .frame(height: capHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            onPress(definition.key)
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        onRelease(definition.key)
                    }
            )
            .onHover { isHovered = $0 }                      // trackpad / Apple Pencil hover
            .accessibilityElement()
            .accessibilityLabel(Text(definition.label))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                onPress(definition.key)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { onRelease(definition.key) }
            }
    }
}

/// The directional pad: four keys arranged in a diamond around a round centre.
struct ArrowPadView: View {
    let size: CGFloat
    let onPress: (CalculatorKey) -> Void
    let onRelease: (CalculatorKey) -> Void

    var body: some View {
        let k = size * 0.34
        ZStack {
            Circle().fill(Color(white: 0.12)).frame(width: size, height: size)
            arrow(.up, "chevron.up").offset(y: -size * 0.31)
            arrow(.down, "chevron.down").offset(y: size * 0.31)
            arrow(.left, "chevron.left").offset(x: -size * 0.31)
            arrow(.right, "chevron.right").offset(x: size * 0.31)
            Circle().fill(Color(white: 0.2)).frame(width: k * 0.7, height: k * 0.7)
        }
        .frame(width: size, height: size)
    }

    private func arrow(_ key: CalculatorKey, _ symbol: String) -> some View {
        ArrowKey(key: key, symbol: symbol, size: size * 0.34, onPress: onPress, onRelease: onRelease)
    }
}

private struct ArrowKey: View {
    let key: CalculatorKey
    let symbol: String
    let size: CGFloat
    let onPress: (CalculatorKey) -> Void
    let onRelease: (CalculatorKey) -> Void
    @State private var isPressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(KeyStyle.arrow.capColor)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.4, weight: .bold)).foregroundColor(.white))
            .brightness(isPressed ? -0.18 : 0)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed { isPressed = true; onPress(key) }
                    }
                    .onEnded { _ in
                        isPressed = false
                        onRelease(key)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(Text(symbol.replacingOccurrences(of: "chevron.", with: "")))
    }
}
