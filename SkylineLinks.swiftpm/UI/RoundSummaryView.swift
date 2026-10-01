import SwiftUI

struct RoundSummaryView: View {
    let result: RoundResult
    let reward: RewardBreakdown
    let coins: Int
    let onMenu: () -> Void
    let onCourses: () -> Void

    @State private var revealed = 0
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Text("ROUND COMPLETE")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("\(result.courseName) · \(result.length.title)")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white.opacity(0.7))

                    HStack(spacing: 40) {
                        VStack {
                            Text("SCORE").font(.caption.weight(.heavy)).opacity(0.7)
                            Text(ScoreName.toParString(result.toPar))
                                .font(.system(size: 54, weight: .black, design: .rounded))
                            Text("\(result.totalStrokes) strokes").font(.caption).opacity(0.7)
                        }
                        VStack {
                            Text("TARGET").font(.caption.weight(.heavy)).opacity(0.7)
                            Text(ScoreName.toParString(result.target))
                                .font(.system(size: 54, weight: .black, design: .rounded))
                                .foregroundColor(UIStyle.gold)
                            Text(" ").font(.caption)
                        }
                    }
                    .foregroundColor(.white)

                    Text(result.targetBeaten ? (result.toPar < result.target ? "TARGET BEATEN!" : "TARGET MATCHED!") : "TARGET MISSED")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(result.targetBeaten ? UIStyle.accent : UIStyle.danger)
                        .scaleEffect(appeared ? 1 : 0.4)
                        .opacity(appeared ? 1 : 0)

                    if let unlocked = reward.unlockedCourseName {
                        Label("New course unlocked: \(unlocked)", systemImage: "lock.open.fill")
                            .font(.headline)
                            .foregroundColor(UIStyle.gold)
                    }
                    if reward.newBest {
                        Label("New personal best", systemImage: "trophy.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("REWARDS")
                            .font(.caption.weight(.heavy))
                            .foregroundColor(.white.opacity(0.6))
                        ForEach(Array(reward.lines.enumerated()), id: \.element.id) { i, line in
                            if i < revealed {
                                HStack {
                                    Text(line.label)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text("+\(line.coins)")
                                        .font(.system(size: 16, weight: .heavy).monospacedDigit())
                                        .foregroundColor(UIStyle.gold)
                                }
                                .transition(.move(edge: .leading).combined(with: .opacity))
                            }
                        }
                        Divider().background(Color.white.opacity(0.3))
                        HStack {
                            Text("TOTAL")
                                .font(.headline.weight(.heavy))
                                .foregroundColor(.white)
                            Spacer()
                            CoinLabel(amount: reward.totalCoins, font: .title3)
                        }
                        HStack {
                            Text("XP")
                                .font(.headline.weight(.heavy))
                                .foregroundColor(.white)
                            Spacer()
                            Text("+\(reward.xp)")
                                .font(.title3.weight(.heavy))
                                .foregroundColor(Color(red: 0.5, green: 0.8, blue: 1))
                        }
                        HStack {
                            Text("Balance")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            CoinLabel(amount: coins, font: .caption)
                        }
                    }
                    .panel()

                    VStack(spacing: 10) {
                        Button("CONTINUE", action: onMenu)
                            .buttonStyle(BigButtonStyle())
                        Button("COURSES", action: onCourses)
                            .buttonStyle(BigButtonStyle(color: Color.white.opacity(0.15), foreground: .white))
                    }
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear(perform: animateIn)
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.2)) {
            appeared = true
        }
        for i in 0..<reward.lines.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(i) * 0.25) {
                withAnimation(.easeOut(duration: 0.25)) {
                    revealed = i + 1
                }
                Feedback.shared.play(.coin)
            }
        }
    }
}
