import SwiftUI
import SpriteKit

/// Hosts the SpriteKit scene plus the SwiftUI HUD for one round.
struct GameView: View {
    @ObservedObject var store: GameStore
    let navigate: (AppScreen) -> Void
    @StateObject private var controller: RoundController
    @State private var paused = false
    @State private var reward: RewardBreakdown?
    @State private var showTutorial: Bool

    init(store: GameStore, courseIndex: Int, length: RoundLength, navigate: @escaping (AppScreen) -> Void) {
        self.store = store
        self.navigate = navigate
        let course = CourseDatabase.course(courseIndex)
        _controller = StateObject(wrappedValue: RoundController(course: course, length: length, bag: store.bag(),
                                                               use3D: store.progress.use3D))
        _showTutorial = State(initialValue: store.progress.showTutorial)
    }

    var body: some View {
        ZStack {
            if let scene3D = controller.scene3D {
                Golf3DContainer(renderer: scene3D, paused: paused)
                    .ignoresSafeArea()
            } else if let scene2D = controller.scene2D {
                GameSceneContainer(scene: scene2D, paused: paused)
                    .ignoresSafeArea()
            }

            GameHUD(controller: controller, paused: $paused)

            if let banner = controller.banner {
                VStack {
                    BannerView(banner: banner)
                        .padding(.top, 150)
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .id(banner.id)
            }

            if showTutorial && controller.phase == .aiming && controller.holeIndex == 0 && controller.strokes == 0 {
                TutorialCard(is3D: controller.scene3D != nil) {
                    showTutorial = false
                    store.dismissTutorial()
                }
                .transition(.opacity)
            }

            if controller.phase == .holeComplete {
                HoleCompleteCard(controller: controller)
                    .transition(.opacity)
            }

            if paused {
                PauseMenu(onResume: { paused = false }, onQuit: { navigate(.menu) })
                    .transition(.opacity)
            }

            if let reward = reward, let result = controller.finishedResult {
                RoundSummaryView(result: result, reward: reward, coins: store.progress.coins,
                                 onMenu: { navigate(.menu) }, onCourses: { navigate(.courses) })
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: controller.banner)
        .animation(.easeInOut(duration: 0.25), value: controller.phase)
        .animation(.easeInOut(duration: 0.2), value: paused)
        .onAppear {
            // Give SpriteView a moment to size the scene before framing the first hole.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                controller.start()
            }
        }
        .onChange(of: controller.phase) { _, newPhase in
            if newPhase == .roundComplete && reward == nil, let result = controller.finishedResult {
                reward = store.applyRound(result)
                if result.targetBeaten {
                    Feedback.shared.success()
                    Feedback.shared.play(.reveal)
                }
            }
        }
        .statusBarHidden(true)
    }
}

/// Wraps SpriteView so HUD updates never rebuild the scene.
struct GameSceneContainer: View {
    let scene: GolfGameScene
    let paused: Bool

    var body: some View {
        SpriteView(scene: scene, isPaused: paused, preferredFramesPerSecond: 60)
    }
}

struct TutorialCard: View {
    var is3D = false
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text("HOW TO SWING")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(UIStyle.gold)
                step("hand.draw.fill", is3D
                     ? "Drag left/right to aim and up/down to change distance. The yellow ring is your target."
                     : "Drag anywhere on the course to move the yellow target.")
                step("rectangle.stack.fill", "Choose a club at the bottom. A good one is picked for you.")
                step("hand.tap.fill", "HOLD the swing button. Power rises.")
                step("arrow.up.to.line", "RELEASE at the white line for 100% of the aimed distance.")
                step("scope", "TAP again as the needle passes the green PERFECT zone.")
                step("wind", "Wind moves the ball in flight. The dotted line ignores wind.")
                Button("LET'S PLAY") { onDismiss() }
                    .buttonStyle(BigButtonStyle())
                    .padding(.top, 6)
            }
            .padding(22)
            .frame(maxWidth: 460)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(red: 0.08, green: 0.14, blue: 0.12)))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.15)))
            .padding()
        }
    }

    private func step(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(UIStyle.accent)
                .frame(width: 26)
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct HoleCompleteCard: View {
    @ObservedObject var controller: RoundController

    var body: some View {
        let last = controller.scores.last
        let isLastHole = controller.holeIndex + 1 >= controller.holes.count
        return ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(controller.lastHoleTitle)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundColor((last?.toPar ?? 0) < 0 ? UIStyle.gold : .white)
                    .shadow(color: .black, radius: 4)
                if let s = last {
                    Text("Hole \(controller.hole.number) · \(s.strokes) strokes · Par \(s.par)")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.85))
                }
                HStack(spacing: 30) {
                    VStack {
                        Text("YOU").font(.caption.weight(.heavy)).opacity(0.7)
                        Text(ScoreName.toParString(controller.completedToPar))
                            .font(.system(size: 30, weight: .black, design: .rounded))
                    }
                    VStack {
                        Text(controller.course.rivalName.uppercased()).font(.caption.weight(.heavy)).opacity(0.7)
                        Text(ScoreName.toParString(controller.rivalToParSoFar))
                            .font(.system(size: 30, weight: .black, design: .rounded))
                    }
                    VStack {
                        Text("TARGET").font(.caption.weight(.heavy)).opacity(0.7)
                        Text(ScoreName.toParString(controller.target))
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundColor(UIStyle.gold)
                    }
                }
                .foregroundColor(.white)
                ScorecardView(holes: controller.holes, scores: controller.scores)
                Button(isLastHole ? "FINISH ROUND" : "NEXT HOLE") {
                    controller.continueAfterHole()
                }
                .buttonStyle(BigButtonStyle())
                .frame(maxWidth: 320)
            }
            .padding(22)
            .frame(maxWidth: 560)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(red: 0.07, green: 0.13, blue: 0.11).opacity(0.95)))
            .padding()
        }
    }
}

struct ScorecardView: View {
    let holes: [GolfHole]
    let scores: [HoleScore]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(0..<holes.count, id: \.self) { i in
                    VStack(spacing: 3) {
                        Text("\(i + 1)")
                            .font(.caption2.weight(.heavy))
                            .foregroundColor(.white.opacity(0.6))
                        Text("\(holes[i].par)")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.white.opacity(0.8))
                        scoreCell(i)
                    }
                    .frame(width: 30)
                }
            }
            .padding(8)
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
    }

    @ViewBuilder
    private func scoreCell(_ i: Int) -> some View {
        if i < scores.count {
            let s = scores[i]
            Text("\(s.strokes)")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(
                    Group {
                        if s.toPar < 0 {
                            Circle().fill(s.toPar <= -2 ? UIStyle.gold : Color.red.opacity(0.8))
                        } else if s.toPar > 0 {
                            RoundedRectangle(cornerRadius: 3).fill(Color.blue.opacity(0.6))
                        } else {
                            Color.clear
                        }
                    }
                )
        } else {
            Text("-")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 24, height: 24)
        }
    }
}

struct PauseMenu: View {
    let onResume: () -> Void
    let onQuit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("PAUSED")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Button("RESUME", action: onResume)
                    .buttonStyle(BigButtonStyle())
                Button("QUIT ROUND", action: onQuit)
                    .buttonStyle(BigButtonStyle(color: UIStyle.danger, foreground: .white))
                Text("Quitting ends the round without rewards.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(red: 0.08, green: 0.14, blue: 0.12)))
        }
    }
}
