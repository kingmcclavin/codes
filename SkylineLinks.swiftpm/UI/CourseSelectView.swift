import SwiftUI

struct CourseSelectView: View {
    @ObservedObject var store: GameStore
    let navigate: (AppScreen) -> Void
    @State private var length: RoundLength = .front

    var body: some View {
        ZStack {
            UIStyle.background.ignoresSafeArea()
            VStack(spacing: 12) {
                ScreenHeader(title: "Courses", coins: store.progress.coins) { navigate(.menu) }
                Picker("Round", selection: $length) {
                    ForEach(RoundLength.allCases) { len in
                        Text(len.title).tag(len)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(0..<CourseDatabase.count, id: \.self) { i in
                            courseCard(i)
                        }
                    }
                    .padding()
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func courseCard(_ i: Int) -> some View {
        let info = CourseDatabase.infos[i]
        let unlocked = store.progress.isUnlocked(courseIndex: i)
        let best = store.progress.bestScore(courseID: info.id, length: length)
        let beaten = store.progress.hasBeaten(courseID: info.id, length: length)
        return Button {
            if unlocked {
                navigate(.playing(courseIndex: i, length: length))
            } else {
                Feedback.shared.warning()
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [info.theme.skyTop.color, info.theme.fairway.color],
                                             startPoint: .top, endPoint: .bottom))
                    Ellipse()
                        .fill(info.theme.green.color)
                        .frame(width: 34, height: 22)
                        .offset(y: 8)
                    Ellipse()
                        .fill(info.theme.water.color.opacity(0.9))
                        .frame(width: 20, height: 10)
                        .offset(x: -18, y: 18)
                    Text("\(i + 1)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(radius: 3)
                        .offset(y: -12)
                }
                .frame(width: 84, height: 84)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(info.name)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        if beaten {
                            Image(systemName: "checkmark.seal.fill").foregroundColor(UIStyle.accent)
                        }
                    }
                    Text(info.tagline)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                    HStack(spacing: 10) {
                        difficultyDots(info.difficulty)
                        Text("Rival: \(info.rivalName)")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    HStack(spacing: 12) {
                        Label("Target \(unlocked ? ScoreName.toParString(CourseDatabase.course(i).target(for: length)) : "?")", systemImage: "flag.fill")
                        if let best = best {
                            Label("Best \(ScoreName.toParString(best))", systemImage: "trophy.fill")
                        }
                    }
                    .font(.caption.weight(.bold))
                    .foregroundColor(UIStyle.gold)
                }
                Spacer()
                Image(systemName: unlocked ? "play.circle.fill" : "lock.fill")
                    .font(.system(size: 30))
                    .foregroundColor(unlocked ? UIStyle.accent : .white.opacity(0.4))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(unlocked ? 0.09 : 0.04))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            )
            .opacity(unlocked ? 1 : 0.6)
        }
        .buttonStyle(.plain)
    }

    private func difficultyDots(_ d: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<10, id: \.self) { k in
                Circle()
                    .fill(k < d ? Color.orange : Color.white.opacity(0.2))
                    .frame(width: 5, height: 5)
            }
        }
    }
}
