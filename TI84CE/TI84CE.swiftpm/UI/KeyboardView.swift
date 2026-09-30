import SwiftUI

/// The TI-84 Plus CE keypad. Every key maps to a position in the emulated keypad
/// matrix; the ROM's keyboard driver scans the matrix and interprets the keys.
struct KeyboardView: View {
    /// Width available for the keypad.
    let width: CGFloat
    let onPress: (CalculatorKey) -> Void
    let onRelease: (CalculatorKey) -> Void

    private var column: CGFloat { width / 5 }
    private var keyWidth: CGFloat { column * 0.84 }
    private var capHeight: CGFloat { keyWidth * 0.52 }
    private var rowSpacing: CGFloat { capHeight * 0.18 }

    /// Height the keypad needs for a given width (used to lay out the body).
    static func height(forWidth width: CGFloat) -> CGFloat {
        let key = width / 5 * 0.84
        let cap = key * 0.52
        let legend = max(7, cap * 0.26) * 1.2 + cap * 0.06
        let row = cap + legend
        let spacing = cap * 0.18
        // graph row + 2 control rows + 7 main rows, plus spacing and separators.
        return row * 10 + spacing * 9 + cap * 0.9
    }

    var body: some View {
        VStack(spacing: rowSpacing) {
            row(KeyLayout.graphRow)
                .padding(.bottom, capHeight * 0.45)
            HStack(alignment: .center, spacing: 0) {
                VStack(spacing: rowSpacing) {
                    ForEach(0..<KeyLayout.controlRows.count, id: \.self) { i in
                        HStack(spacing: 0) {
                            ForEach(KeyLayout.controlRows[i]) { cell($0) }
                        }
                    }
                }
                ArrowPadView(size: column * 1.85, onPress: onPress, onRelease: onRelease)
                    .frame(width: column * 2)
            }
            .padding(.bottom, capHeight * 0.45)
            ForEach(0..<KeyLayout.mainRows.count, id: \.self) { i in
                row(KeyLayout.mainRows[i])
            }
        }
        .frame(width: width)
    }

    private func row(_ keys: [KeyDefinition]) -> some View {
        HStack(spacing: 0) {
            ForEach(keys) { cell($0) }
        }
    }

    private func cell(_ d: KeyDefinition) -> some View {
        KeyView(definition: d, width: keyWidth, capHeight: capHeight, onPress: onPress, onRelease: onRelease)
            .frame(width: column)
    }
}
