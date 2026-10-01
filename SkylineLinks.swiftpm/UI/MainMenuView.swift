import SwiftUI

struct MainMenuView: View {
    @ObservedObject var store: GameStore
    let navigate: (AppScreen) -> Void
    @State private var bob = false

    private var nextCourse: CourseInfo {
        CourseDatabase.infos[store.progress.currentCampaignIndex]
    }

    var body: some View {
        ZStack {
            UIStyle.background.ignoresSafeArea()
            MenuBackdrop()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    header
                    titleBlock
                    playCard
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            menuTile("CLUBS", icon: "rectangle.stack.fill", color: Color(red: 0.35, green: 0.6, blue: 1)) { navigate(.clubs) }
                            menuTile("PACKS", icon: "gift.fill", color: Color(red: 0.95, green: 0.55, blue: 0.2)) { navigate(.packs) }
                        }
                        HStack(spacing: 12) {
                            menuTile("COURSES", icon: "map.fill", color: Color(red: 0.4, green: 0.8, blue: 0.5)) { navigate(.courses) }
                            menuTile("SETTINGS", icon: "gearshape.fill", color: Color(red: 0.6, green: 0.6, blue: 0.7)) { navigate(.settings) }
                        }
                    }
                    statsRow
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { bob = true }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("LEVEL \(store.progress.playerLevel)")
                    .font(.caption.weight(.heavy))
                    .foregroundColor(.white.opacity(0.8))
                ProgressView(value: Double(store.progress.xpIntoLevel), total: Double(PlayerProgress.xpPerLevel))
                    .tint(UIStyle.accent)
                    .frame(width: 120)
            }
            Spacer()
            CoinLabel(amount: store.progress.coins, font: .title3)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.35)))
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 54, height: 54)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 6)
                    .offset(y: bob ? -10 : 4)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: bob)
            }
            .frame(height: 70)
            Text("SKYLINE LINKS")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.75, green: 1, blue: 0.7)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("Arcade Golf Tour")
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.vertical, 8)
    }

    private var playCard: some View {
        let course = nextCourse
        let index = store.progress.currentCampaignIndex
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CAMPAIGN · COURSE \(index + 1)")
                        .font(.caption.weight(.heavy))
                        .foregroundColor(.white.opacity(0.7))
                    Text(course.name)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text(course.tagline)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.75))
                }
                Spacer()
            }
            HStack(spacing: 10) {
                ForEach(RoundLength.allCases) { len in
                    Button {
                        navigate(.playing(courseIndex: index, length: len))
                    } label: {
                        VStack(spacing: 2) {
                            Text(len == .quick ? "PLAY" : len.title.uppercased())
                                .font(.system(size: len == .quick ? 22 : 15, weight: .heavy, design: .rounded))
                            Text(len == .quick ? "3 holes" : "Target \(ScoreName.toParString(CourseDatabase.course(index).target(for: len)))")
                                .font(.caption2.weight(.bold))
                                .opacity(0.8)
                        }
                        .foregroundColor(len == .quick ? .black : .white)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(len == .quick ? UIStyle.accent : Color.white.opacity(0.14))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [course.theme.skyTop.color.opacity(0.55), course.theme.fairway.color.opacity(0.45)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 1))
        )
    }

    private func menuTile(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .bold))
                Text(title)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(color.opacity(0.35))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(color.opacity(0.7), lineWidth: 1.5))
            )
        }
        .buttonStyle(.plain)
    }

    private var statsRow: some View {
        HStack {
            statItem("\(store.progress.roundsPlayed)", "Rounds")
            statItem("\(store.progress.birdiesOrBetter)", "Birdies+")
            statItem("\(store.progress.holesInOne)", "Aces")
            statItem("\(store.progress.cards.count)/\(ClubCatalog.all.count)", "Cards")
        }
        .panel()
    }

    private func statItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.heavy).monospacedDigit())
                .foregroundColor(.white)
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

/// Soft rolling hills drawn with SwiftUI shapes.
struct MenuBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.72))
                    p.addCurve(to: CGPoint(x: w, y: h * 0.66),
                               control1: CGPoint(x: w * 0.3, y: h * 0.6),
                               control2: CGPoint(x: w * 0.6, y: h * 0.78))
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.closeSubpath()
                }
                .fill(Color(red: 0.12, green: 0.32, blue: 0.16).opacity(0.7))
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.84))
                    p.addCurve(to: CGPoint(x: w, y: h * 0.8),
                               control1: CGPoint(x: w * 0.4, y: h * 0.74),
                               control2: CGPoint(x: w * 0.7, y: h * 0.9))
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.closeSubpath()
                }
                .fill(Color(red: 0.18, green: 0.45, blue: 0.2).opacity(0.7))
            }
        }
        .allowsHitTesting(false)
    }
}
