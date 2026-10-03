import SwiftUI

/// Small, non-blocking capsule that reports a blocked popup or navigation.
struct BlockedToast: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "hand.raised.fill")
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .allowsHitTesting(false)
    }
}
