import SwiftUI

/// A collectible card face.
struct ClubCardView: View {
    let card: ClubCardDefinition
    let level: Int
    var copies: Int? = nil
    var equipped = false
    var compact = false

    var body: some View {
        let stats = card.stats.leveled(level)
        let club = EquippedClub(card: card, level: level)
        let rarity = card.rarity.color.color
        return VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            HStack {
                Text(card.type.shortName)
                    .font(.system(size: compact ? 12 : 14, weight: .black, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(rarity))
                    .foregroundColor(.black)
                Spacer()
                Text("LV \(level)")
                    .font(.system(size: compact ? 11 : 13, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }
            Text(card.name.uppercased())
                .font(.system(size: compact ? 14 : 19, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(card.rarity.displayName.uppercased())
                .font(.caption2.weight(.heavy))
                .foregroundColor(rarity)
            if !compact {
                VStack(spacing: 5) {
                    StatBar(label: "POWER", value: stats.power, color: .orange)
                    StatBar(label: "ACCURACY", value: stats.accuracy, color: .cyan)
                    StatBar(label: "FORGIVE", value: stats.forgiveness, color: .green)
                    if card.type != .putter {
                        StatBar(label: "SPIN", value: stats.spin, color: .pink)
                    }
                    StatBar(label: "CONTROL", value: stats.control, color: .purple)
                }
                Text(card.type == .putter ? "Max putt \(Int(club.carry)) yds" : "Distance \(Int(club.carry)) yds")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white.opacity(0.85))
                if card.abilities.isEmpty {
                    Text("No ability")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                } else {
                    ForEach(Array(card.abilities.enumerated()), id: \.offset) { _, ability in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ability.name.uppercased())
                                .font(.caption2.weight(.black))
                                .foregroundColor(UIStyle.gold)
                            Text(ability.describe(level: level))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white)
                        }
                    }
                }
            } else {
                Text("\(Int(club.carry)) yds")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white.opacity(0.8))
                if let first = card.abilities.first {
                    Text(first.describe(level: level))
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(UIStyle.gold)
                        .lineLimit(2)
                }
            }
            if let copies = copies {
                let need = UpgradeRules.copies(toLevelUpFrom: level)
                let maxed = level >= card.rarity.maxLevel
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: Double(min(copies, need)), total: Double(need))
                        .tint(copies >= need ? UIStyle.gold : rarity)
                    Text(maxed ? "MAX LEVEL" : "Cards \(copies) / \(need)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(compact ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [rarity.opacity(0.45), Color.black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(equipped ? UIStyle.accent : rarity.opacity(0.9), lineWidth: equipped ? 3 : 1.5)
        )
        .overlay(alignment: .topTrailing) {
            if equipped {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(UIStyle.accent)
                    .background(Circle().fill(Color.black))
                    .offset(x: 6, y: -6)
            }
        }
    }
}

struct ClubCollectionView: View {
    @ObservedObject var store: GameStore
    let navigate: (AppScreen) -> Void
    @State private var selectedType: ClubType = .driver
    @State private var detailCardID: String?

    var body: some View {
        ZStack {
            UIStyle.background.ignoresSafeArea()
            VStack(spacing: 10) {
                ScreenHeader(title: "Clubs", coins: store.progress.coins) { navigate(.menu) }
                typePicker
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("IN YOUR BAG")
                            .font(.caption.weight(.heavy))
                            .foregroundColor(.white.opacity(0.6))
                        let equippedCard = store.progress.equippedCard(for: selectedType)
                        Button {
                            detailCardID = equippedCard.id
                        } label: {
                            ClubCardView(card: equippedCard, level: level(of: equippedCard.id),
                                         copies: copies(of: equippedCard.id), equipped: true)
                                .frame(maxWidth: 360)
                        }
                        .buttonStyle(.plain)

                        Text("COLLECTION · \(selectedType.displayName.uppercased())")
                            .font(.caption.weight(.heavy))
                            .foregroundColor(.white.opacity(0.6))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                            ForEach(cardsForType) { card in
                                cardTile(card)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .sheet(item: Binding(get: { detailCardID.map { IdentifiedString(id: $0) } },
                             set: { detailCardID = $0?.id })) { item in
            ClubDetailView(store: store, cardID: item.id)
        }
    }

    private var typePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ClubType.allCases) { type in
                    Button {
                        selectedType = type
                    } label: {
                        Text(type.shortName)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(selectedType == type ? .black : .white)
                            .frame(width: 52, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selectedType == type ? UIStyle.accent : Color.white.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private var cardsForType: [ClubCardDefinition] {
        ClubCatalog.all.filter { $0.type == selectedType }
            .sorted { a, b in
                let oa = store.progress.owns(a.id)
                let ob = store.progress.owns(b.id)
                if oa != ob { return oa }
                return a.rarity < b.rarity
            }
    }

    private func level(of id: String) -> Int { store.progress.cards[id]?.level ?? 1 }
    private func copies(of id: String) -> Int { store.progress.cards[id]?.copies ?? 0 }

    @ViewBuilder
    private func cardTile(_ card: ClubCardDefinition) -> some View {
        if store.progress.owns(card.id) {
            Button {
                detailCardID = card.id
            } label: {
                ClubCardView(card: card, level: level(of: card.id), copies: copies(of: card.id),
                             equipped: store.progress.equipped[card.type.rawValue] == card.id, compact: true)
                    .frame(height: 190)
            }
            .buttonStyle(.plain)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "questionmark")
                    .font(.system(size: 30, weight: .black))
                Text(card.rarity.displayName.uppercased())
                    .font(.caption.weight(.heavy))
                Text("Find in packs")
                    .font(.caption2)
                    .opacity(0.7)
            }
            .foregroundColor(card.rarity.color.color.opacity(0.8))
            .frame(maxWidth: .infinity, minHeight: 190)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(card.rarity.color.color.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
        }
    }
}

struct IdentifiedString: Identifiable {
    let id: String
}

struct ClubDetailView: View {
    @ObservedObject var store: GameStore
    let cardID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            UIStyle.background.ignoresSafeArea()
            if let card = ClubCatalog.card(cardID) {
                let owned = store.progress.cards[cardID] ?? OwnedCard(level: 1, copies: 0)
                let isEquipped = store.progress.equipped[card.type.rawValue] == cardID
                let maxed = owned.level >= card.rarity.maxLevel
                let need = UpgradeRules.copies(toLevelUpFrom: owned.level)
                let cost = UpgradeRules.coins(toLevelUpFrom: owned.level)
                ScrollView {
                    VStack(spacing: 18) {
                        HStack {
                            Spacer()
                            Button("Done") { dismiss() }
                                .font(.headline)
                                .foregroundColor(UIStyle.accent)
                        }
                        ClubCardView(card: card, level: owned.level, copies: owned.copies, equipped: isEquipped)
                            .frame(maxWidth: 380)
                        if !card.flavor.isEmpty {
                            Text("“\(card.flavor)”")
                                .font(.callout.italic())
                                .foregroundColor(.white.opacity(0.7))
                        }
                        if !maxed {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("NEXT LEVEL (\(owned.level + 1))")
                                    .font(.caption.weight(.heavy))
                                    .foregroundColor(.white.opacity(0.6))
                                Text("All stats +1.6")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                ForEach(Array(card.abilities.enumerated()), id: \.offset) { _, a in
                                    Text("\(a.describe(level: owned.level)) → \(a.describe(level: owned.level + 1))")
                                        .font(.subheadline)
                                        .foregroundColor(UIStyle.gold)
                                }
                            }
                            .frame(maxWidth: 380, alignment: .leading)
                            .panel()
                        }
                        VStack(spacing: 10) {
                            if !isEquipped {
                                Button("EQUIP") {
                                    store.equip(cardID)
                                }
                                .buttonStyle(BigButtonStyle())
                            }
                            if !maxed {
                                Button {
                                    _ = store.upgrade(cardID)
                                } label: {
                                    HStack {
                                        Text("UPGRADE")
                                        Text("· \(owned.copies)/\(need) cards · \(cost) coins")
                                            .font(.system(size: 14, weight: .bold))
                                    }
                                }
                                .buttonStyle(BigButtonStyle(color: UIStyle.gold))
                                .disabled(!store.progress.canUpgrade(cardID))
                                .opacity(store.progress.canUpgrade(cardID) ? 1 : 0.45)
                            }
                        }
                        .frame(maxWidth: 380)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
