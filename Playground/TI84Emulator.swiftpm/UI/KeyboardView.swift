#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

/// The full TI-84 Plus keypad, sized from the available width.
struct KeyboardView: View {
    let width: CGFloat
    let onPress: (Key) -> Void
    let onRelease: (Key) -> Void
    var haptics = true

    private var spacing: CGFloat { width * 0.035 }
    private var keyWidth: CGFloat { (width - spacing * 4) / 5 }

    var body: some View {
        VStack(spacing: spacing * 0.7) {
            row(KeyLayout.graphRow, width: keyWidth * 0.92)
                .padding(.bottom, spacing * 0.6)

            // 2ND/MODE/DEL and ALPHA/X,T,θ,n/STAT beside the arrow pad.
            HStack(alignment: .center, spacing: spacing) {
                VStack(spacing: spacing * 0.7) {
                    ForEach(0..<KeyLayout.upperLeft.count, id: \.self) { index in
                        row(KeyLayout.upperLeft[index], width: keyWidth)
                    }
                }
                ArrowPad(size: keyWidth * 1.95 + spacing, onPress: onPress, onRelease: onRelease, haptics: haptics)
            }

            ForEach(0..<KeyLayout.mainRows.count, id: \.self) { index in
                row(KeyLayout.mainRows[index], width: keyWidth)
            }
        }
        .frame(width: width)
    }

    private func row(_ keys: [KeyDefinition], width keyWidth: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(keys) { definition in
                KeyView(definition: definition, width: keyWidth, onPress: onPress, onRelease: onRelease,
                        haptics: haptics)
            }
        }
    }
}
#endif
