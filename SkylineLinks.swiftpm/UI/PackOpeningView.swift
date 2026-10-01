import SwiftUI

struct PackShopView: View {
    @ObservedObject var store: GameStore
    let navigate: (AppScreen) -> Void
    @State private var reveals: [PackReveal] = []
    @State private var openedPack: PackType?

    var body: some View {
        ZStack {
            UIStyle.background.ignoresSafeArea()
            VStack(spacing: 10) {
                ScreenHeader(title: "Packs", coins: store.progress.coins) { navigate(.menu) }
                ScrollView {
                    VStack(spacing: 16) {
                        Text("Earn coins by playing rounds. Duplicate cards level up your clubs.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                        ForEach(PackType.allCases) { pack in
                            packCard(pack)
                        }
                    }
                    .padding()
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
            }
            if let pack = openedPack, !reveals.isEmpty {
                PackRevealView(pack: pack, reveals: reveals) {
                    reveals = []
                    openedPack = nil
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: reveals.count)
    }

    private func packCard(_ pack: PackType) -> some View {
        let affordable = store.progress.coins >= pack.price
        return HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [pack.color.color, pack.color.shaded(0.5).color], startPoint: .top, endPoint: .bottom))
                    .frame(width: 86, height: 116)
                    .shadow(color: pack.color.color.opacity(0.5), radius: 10, y: 5)
                VStack(spacing: 4) {
                    Image(systemName: "seal.fill")
                        .font(.system(size: 28))
                    Text("\(pack.cardCount)")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                    Text("CARDS")
                        .font(.caption2.weight(.heavy))
                }
                .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(pack.displayName.uppercased())
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("ODDS PER CARD")
                    .font(.caption2.weight(.heavy))
                    .foregroundColor(.white.opacity(0.55))
                ForEach(pack.odds.indices, id: \.self) { i in
                    let pair = pack.odds[i]
                    HStack {
                        Circle().fill(pair.0.color.color).frame(width: 8, height: 8)
                        Text(pair.0.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                        Spacer()
                        Text(String(format: "%.0f%%", pair.1 * 100))
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundColor(.white)
                    }
                }
                Button {
                    if let r = store.buyPack(pack) {
                        openedPack = pack
                        reveals = r
                        Feedback.shared.play(.coin)
                    } else {
                        Feedback.shared.warning()
                    }
                } label: {
                    HStack {
                        Text("OPEN")
                        Spacer()
                        CoinLabel(amount: pack.price, font: .subheadline)
                    }
                    .padding(.horizontal, 6)
                }
                .buttonStyle(BigButtonStyle(color: affordable ? UIStyle.accent : Color.gray.opacity(0.5)))
                .disabled(!affordable)
            }
        }
        .panel()
    }
}

/// Reveals cards one at a time with a flip.
struct PackRevealView: View {
    let pack: PackType
    let reveals: [PackReveal]
    let onDone: () -> Void
    @State private var shown = 0
    @State private var flipped = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 20) {
                Text(pack.displayName.uppercased())
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("Card \(min(shown + 1, reveals.count)) of \(reveals.count)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white.opacity(0.6))

                if shown < reveals.count {
                    let r = reveals[shown]
                    ZStack {
                        if flipped {
                            VStack(spacing: 8) {
                                Text(r.isNew ? "NEW CARD!" : "+1 COPY")
                                    .font(.system(size: 18, weight: .black, design: .rounded))
                                    .foregroundColor(r.isNew ? UIStyle.gold : UIStyle.accent)
                                ClubCardView(card: r.card, level: r.level, copies: r.copies)
                                    .frame(width: 300)
                                if !r.isNew && r.copies >= r.copiesNeeded {
                                    Text("Ready to upgrade!")
                                        .font(.headline)
                                        .foregroundColor(UIStyle.gold)
                                }
                            }
                            .transition(.scale.combined(with: .opacity))
                        } else {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(LinearGradient(colors: [pack.color.color, pack.color.shaded(0.4).color], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 240, height: 330)
                                .overlay(
                                    VStack {
                                        Image(systemName: "questionmark.diamond.fill").font(.system(size: 60))
                                        Text("TAP TO REVEAL").font(.headline.weight(.heavy))
                                    }
                                    .foregroundColor(.white)
                                )
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(r.card.rarity.color.color, lineWidth: 4))
                                .shadow(color: r.card.rarity.color.color.opacity(0.8), radius: 20)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(minHeight: 420)
                    .onTapGesture { advance() }
                }

                Button(buttonTitle) { advance() }
                    .buttonStyle(BigButtonStyle())
                    .frame(maxWidth: 320)
            }
            .padding()
        }
    }

    private var buttonTitle: String {
        if !flipped { return "REVEAL" }
        return shown + 1 < reveals.count ? "NEXT CARD" : "DONE"
    }

    private func advance() {
        if !flipped {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { flipped = true }
            Feedback.shared.play(.reveal)
            if let r = reveals[safe: shown], r.card.rarity >= .epic {
                Feedback.shared.success()
            } else {
                Feedback.shared.impact(.medium)
            }
        } else if shown + 1 < reveals.count {
            withAnimation(.easeInOut(duration: 0.2)) {
                shown += 1
                flipped = false
            }
        } else {
            onDone()
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
