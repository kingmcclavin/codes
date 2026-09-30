import SwiftUI

/// The TI-84 Plus CE keypad. Every key maps to a position in the emulated keypad
/// matrix; the ROM's keyboard driver scans the matrix and interprets the keys.
struct KeyboardView: View {
    /// Width available for the keypad.
    let width: CGFloat
    /// Height to fill. When nil, keys use their natural proportions for `width`.
    var height: CGFloat? = nil
    let onPress: (CalculatorKey) -> Void
    let onRelease: (CalculatorKey) -> Void

    private var column: CGFloat { width / 5 }
    private var keyWidth: CGFloat { column * 0.84 }
    private var capHeight: CGFloat {
        guard let height else { return keyWidth * 0.52 }
        return KeyboardView.capHeight(toFill: height, width: width)
    }
    private var rowSpacing: CGFloat { capHeight * 0.18 }

    /// Smallest / largest key-cap height relative to key width.
    static let capRange: ClosedRange<CGFloat> = 0.40...0.78

    static func rowHeight(capHeight cap: CGFloat) -> CGFloat {
        cap + max(7, cap * 0.26) * 1.2 + cap * 0.06
    }

    /// Size of the arrow pad: slightly taller than the two control rows beside it.
    static func arrowPadSize(capHeight cap: CGFloat, width: CGFloat) -> CGFloat {
        let block = rowHeight(capHeight: cap) * 2 + cap * 0.18
        return min(width / 5 * 1.85, block * 1.3)
    }

    /// Total keypad height for a given key-cap height and width.
    static func height(capHeight cap: CGFloat, width: CGFloat) -> CGFloat {
        let row = rowHeight(capHeight: cap)
        let spacing = cap * 0.18
        let block = row * 2 + spacing
        let padOverflow = max(0, arrowPadSize(capHeight: cap, width: width) - block)
        // graph row + 2 control rows + 7 main rows, plus spacing and separators.
        return row * 10 + spacing * 9 + cap * 0.9 + padOverflow
    }

    /// Height the keypad needs for a given width with natural key proportions.
    static func height(forWidth width: CGFloat) -> CGFloat {
        height(capHeight: width / 5 * 0.84 * 0.52, width: width)
    }

    /// Smallest height the keypad can shrink to at this width.
    static func minimumHeight(forWidth width: CGFloat) -> CGFloat {
        height(capHeight: width / 5 * 0.84 * capRange.lowerBound, width: width)
    }

    /// Key-cap height that makes the keypad exactly `height` tall (within limits).
    static func capHeight(toFill height: CGFloat, width: CGFloat) -> CGFloat {
        let key = width / 5 * 0.84
        var lo = key * capRange.lowerBound, hi = key * capRange.upperBound
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if KeyboardView.height(capHeight: mid, width: width) <= height { lo = mid } else { hi = mid }
        }
        return lo
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
                ArrowPadView(size: KeyboardView.arrowPadSize(capHeight: capHeight, width: width), onPress: onPress, onRelease: onRelease)
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
