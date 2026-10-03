import SwiftUI

/// Small, non-blocking capsule that reports a blocked popup or redirect.
/// When `onOpen` is set, the user can open the blocked page anyway.
struct BlockedToast: View {
    let text: String
    var onOpen: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            Label(text, systemImage: "hand.raised.fill")
                .font(.callout.weight(.medium))
                .lineLimit(1)
            if let onOpen {
                Button("Open", action: onOpen)
                    .font(.callout.weight(.semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, onOpen == nil ? 18 : 8)
        .padding(.vertical, onOpen == nil ? 10 : 6)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.horizontal, 16)
    }
}
