import SwiftUI

/// Everything drawn over the SpriteKit course during play.
struct GameHUD: View {
    @ObservedObject var controller: RoundController
    @Binding var paused: Bool

    var body: some View {
        VStack(spacing: 8) {
            topBar
            infoRow
            Spacer(minLength: 0)
            bottomPanel
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    // MARK: Top

    private var topBar: some View {
        let h = controller.hole
        let currentToPar = controller.completedToPar
        return HStack(alignment: .center, spacing: 10) {
            Button {
                paused = true
            } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.black.opacity(0.45)))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("HOLE \(h.number)/\(controller.holes.count)")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                Text("PAR \(h.par) · \(h.yardage) YDS")
                    .font(.caption.weight(.bold))
                    .opacity(0.85)
                Text("Strokes: \(controller.strokes)")
                    .font(.caption2.weight(.bold))
                    .opacity(0.75)
            }

            Spacer(minLength: 4)

            HStack(spacing: 12) {
                scoreBlock(title: "YOU", value: ScoreName.toParString(currentToPar), color: .white)
                scoreBlock(title: "TARGET", value: ScoreName.toParString(controller.target), color: UIStyle.gold)
            }

            Spacer(minLength: 4)

            WindBadge(wind: h.wind, viewRotation: controller.viewRotation)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.45)))
    }

    private func scoreBlock(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption2.weight(.heavy))
                .opacity(0.7)
            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded).monospacedDigit())
                .foregroundColor(color)
        }
    }

    private var infoRow: some View {
        HStack(spacing: 6) {
            chip(controller.lie.displayName, icon: "leaf.fill", color: lieColor)
            chip("Pin \(Int(controller.distanceToPin.rounded()))y", icon: "flag.fill", color: .white)
            if controller.phase == .aiming || controller.phase == .swinging {
                chip("Aim \(Int(controller.targetDistance.rounded()))y", icon: "scope", color: Color(red: 1, green: 0.85, blue: 0.3))
                if !controller.isPutting && abs(controller.playsLike - controller.targetDistance) >= 3 {
                    chip("Plays \(Int(controller.playsLike.rounded()))y", icon: "arrow.up.right", color: .orange)
                }
            }
            Spacer(minLength: 0)
            Button {
                controller.resetAim()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .hudIconStyle()
            }
            Button {
                controller.toggleOverview()
            } label: {
                Image(systemName: controller.overview ? "eye.slash.fill" : "eye.fill")
                    .hudIconStyle()
            }
        }
    }

    private var lieColor: Color {
        switch controller.lie {
        case .tee, .fairway, .green, .fringe: return UIStyle.accent
        case .rough: return .yellow
        case .heavyRough, .sand: return .orange
        default: return .red
        }
    }

    private func chip(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(text).font(.system(size: 13, weight: .heavy, design: .rounded)).lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.5)))
    }

    // MARK: Bottom

    private var bottomPanel: some View {
        VStack(spacing: 8) {
            SwingMeterView(meter: controller.meter)
                .opacity(controller.phase == .aiming || controller.phase == .swinging ? 1 : 0.35)
            HStack(alignment: .center, spacing: 12) {
                ClubInfoView(club: controller.currentClub, lie: controller.lie)
                Spacer(minLength: 0)
                SwingButton(controller: controller, meter: controller.meter)
            }
            ClubStrip(controller: controller)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.black.opacity(0.5)))
        .frame(maxWidth: 720)
    }
}

extension Image {
    func hudIconStyle() -> some View {
        self.font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 40, height: 40)
            .background(Circle().fill(Color.black.opacity(0.5)))
    }
}

struct WindBadge: View {
    let wind: Wind
    let viewRotation: Double

    var body: some View {
        VStack(spacing: 2) {
            Text("WIND")
                .font(.caption2.weight(.heavy))
                .opacity(0.7)
            if wind.speedMPH < 0.5 {
                Text("CALM")
                    .font(.system(size: 14, weight: .black, design: .rounded))
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .black))
                        .rotationEffect(.radians(-(wind.direction - viewRotation)))
                        .foregroundColor(Color(red: 0.6, green: 0.85, blue: 1))
                    Text("\(Int(wind.speedMPH)) mph")
                        .font(.system(size: 14, weight: .black, design: .rounded).monospacedDigit())
                }
            }
        }
        .foregroundColor(.white)
        .frame(minWidth: 70)
    }
}

struct ClubInfoView: View {
    let club: EquippedClub
    let lie: Terrain

    var body: some View {
        let mods = club.modifiers(lie: lie, targetDistance: 150)
        let reach = Int((club.carry * mods.reachMultiplier).rounded())
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(club.type.shortName)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(club.card.rarity.color.color))
                Text("LV \(club.level)")
                    .font(.caption2.weight(.heavy))
                    .foregroundColor(.white.opacity(0.7))
            }
            Text(club.card.name)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(club.type.isPutter ? "Max \(reach) yds" : "Max \(reach) yds from \(lie.displayName.lowercased())")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.8))
            if let ability = club.card.abilities.first {
                Text(ability.describe(level: club.level))
                    .font(.caption2.weight(.bold))
                    .foregroundColor(UIStyle.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

struct ClubStrip: View {
    @ObservedObject var controller: RoundController

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ClubType.allCases) { type in
                        chip(type)
                            .id(type)
                    }
                }
                .padding(.horizontal, 2)
            }
            .onChange(of: controller.selectedClub) { _, newValue in
                withAnimation { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }

    private func chip(_ type: ClubType) -> some View {
        let allowed = controller.isClubAllowed(type)
        let selected = controller.selectedClub == type
        let club = controller.bag[type]
        let reach: Int = {
            guard let c = club else { return 0 }
            return Int((c.carry * c.modifiers(lie: controller.lie, targetDistance: 150).reachMultiplier).rounded())
        }()
        let rarity = club?.card.rarity.color.color ?? .gray
        return Button {
            controller.selectClub(type)
        } label: {
            VStack(spacing: 1) {
                Text(type.shortName)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                Text("\(reach)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .opacity(0.8)
            }
            .foregroundColor(selected ? .black : .white)
            .frame(width: 52, height: 46)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? rarity : Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(rarity.opacity(0.8), lineWidth: 1.5)
            )
            .opacity(allowed ? 1 : 0.3)
        }
        .buttonStyle(.plain)
        .disabled(!allowed)
    }
}

/// Hold to charge power, release to lock it, tap again for accuracy.
struct SwingButton: View {
    @ObservedObject var controller: RoundController
    @ObservedObject var meter: SwingMeterModel
    @State private var pressing = false

    private var label: String {
        switch controller.phase {
        case .intro: return "SKIP"
        case .aiming: return meter.isPutt ? "HOLD\nTO PUTT" : "HOLD\nTO SWING"
        case .swinging:
            switch meter.state.phase {
            case .charging: return "RELEASE"
            case .accuracy: return "TAP!"
            default: return "..."
            }
        default: return "..."
        }
    }

    private var active: Bool {
        controller.phase == .aiming || controller.phase == .swinging || controller.phase == .intro
    }

    var body: some View {
        let accuracyPhase = meter.state.phase == .accuracy
        ZStack {
            Circle()
                .fill(
                    RadialGradient(colors: accuracyPhase ? [Color.yellow, Color.orange] : [UIStyle.accent, Color(red: 0.15, green: 0.5, blue: 0.2)],
                                   center: .center, startRadius: 4, endRadius: 60)
                )
                .shadow(color: (accuracyPhase ? Color.yellow : UIStyle.accent).opacity(0.6), radius: pressing ? 4 : 12)
            Circle()
                .stroke(Color.white.opacity(0.7), lineWidth: 3)
            Text(label)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(.black.opacity(0.85))
        }
        .frame(width: 104, height: 104)
        .scaleEffect(pressing ? 0.93 : 1)
        .opacity(active ? 1 : 0.4)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressing {
                        pressing = true
                        controller.swingPressed()
                    }
                }
                .onEnded { _ in
                    pressing = false
                    controller.swingReleased()
                }
        )
        .animation(.easeOut(duration: 0.1), value: pressing)
    }
}

struct SwingMeterView: View {
    @ObservedObject var meter: SwingMeterModel

    private var shownPower: Double {
        switch meter.state.phase {
        case .charging: return meter.state.power
        case .accuracy, .finished: return meter.state.lockedPower
        case .idle: return 0
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            PowerBarView(power: shownPower, isPutt: meter.isPutt)
            if !meter.isPutt {
                AccuracyBarView(windows: meter.windows, needle: meter.state.needle,
                                showNeedle: meter.state.phase == .accuracy || meter.state.phase == .finished)
            }
        }
    }
}

struct PowerBarView: View {
    let power: Double
    let isPutt: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(isPutt ? "PUTT" : "POWER")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 50, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                let maxP = SwingMeterState.maxPower
                let fill = CGFloat(min(power, maxP) / maxP) * w
                let fullX = CGFloat(1.0 / maxP) * w
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(colors: power > 1.0 ? [.yellow, .red] : [Color(red: 0.4, green: 0.9, blue: 0.4), .yellow],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, fill))
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 3)
                        .offset(x: fullX - 1.5)
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 1)
                        .offset(x: fullX * 0.5)
                }
            }
            .frame(height: 16)
            Text("\(Int((power * 100).rounded()))%")
                .font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundColor(.white)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

struct AccuracyBarView: View {
    let windows: TimingWindows
    let needle: Double
    let showNeedle: Bool

    private let range = 1.25

    var body: some View {
        HStack(spacing: 8) {
            Text("TIMING")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 50, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                let mid = w / 2
                ZStack {
                    zone(w: w, half: range, color: Color(red: 0.75, green: 0.2, blue: 0.2))
                    zone(w: w, half: windows.edge, color: .orange)
                    zone(w: w, half: windows.good, color: .yellow)
                    zone(w: w, half: windows.great, color: Color(red: 0.6, green: 0.95, blue: 0.5))
                    zone(w: w, half: windows.perfect, color: Color(red: 0.1, green: 0.85, blue: 0.3))
                    if showNeedle {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 4, height: 24)
                            .shadow(color: .black, radius: 2)
                            .position(x: mid + CGFloat(needle.clamped(-range, range) / range) * mid, y: 8)
                    }
                }
            }
            .frame(height: 16)
            HStack(spacing: 0) {
                Text("E").foregroundColor(.orange)
                Text("·").foregroundColor(.white)
                Text("L").foregroundColor(.orange)
            }
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .frame(width: 44, alignment: .trailing)
        }
    }

    private func zone(w: CGFloat, half: Double, color: Color) -> some View {
        let width = CGFloat(min(half, range) / range) * w
        return RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: max(2, width), height: 16)
            .position(x: w / 2, y: 8)
    }
}

struct BannerView: View {
    let banner: GameBanner

    private var color: Color {
        switch banner.style {
        case .great: return UIStyle.gold
        case .good: return UIStyle.accent
        case .neutral: return .white
        case .bad: return Color(red: 1, green: 0.45, blue: 0.4)
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(banner.title)
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundColor(color)
                .shadow(color: .black.opacity(0.8), radius: 4, y: 3)
                .multilineTextAlignment(.center)
            if let sub = banner.subtitle {
                Text(sub)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.8), radius: 3, y: 2)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Capsule().fill(Color.black.opacity(0.35)))
    }
}
