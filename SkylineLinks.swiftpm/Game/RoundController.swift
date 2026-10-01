import SwiftUI
import SpriteKit

/// Publishes the swing meter separately so only the meter view redraws 60 times per second.
final class SwingMeterModel: ObservableObject {
    @Published private(set) var state = SwingMeterState()
    @Published private(set) var windows = TimingWindows(perfect: 0.08, great: 0.17, good: 0.3)
    @Published private(set) var isPutt = false

    func configure(windows: TimingWindows, isPutt: Bool, speed: Double) {
        var s = SwingMeterState()
        s.isPutt = isPutt
        s.speed = speed
        state = s
        self.windows = windows
        self.isPutt = isPutt
    }

    func touchDown() -> SwingMeterState.Event { state.touchDown() }
    func touchUp() -> SwingMeterState.Event { state.touchUp() }

    func tick(_ dt: Double) -> SwingMeterState.Event {
        guard state.phase == .charging || state.phase == .accuracy else { return .none }
        return state.tick(dt)
    }

    func reset() {
        if state.phase != .idle { state.reset() }
    }
}

struct GameBanner: Identifiable, Equatable {
    enum Style {
        case great
        case good
        case neutral
        case bad
    }

    let id = UUID()
    let title: String
    let subtitle: String?
    let style: Style

    static func == (a: GameBanner, b: GameBanner) -> Bool { a.id == b.id }
}

/// Owns the rules of a round: holes, strokes, penalties, club choice and the swing.
final class RoundController: ObservableObject {
    enum Phase: Equatable {
        case intro
        case aiming
        case swinging
        case ballMoving
        case holeComplete
        case roundComplete
    }

    let course: GolfCourse
    let length: RoundLength
    let holes: [GolfHole]
    let bag: [ClubType: EquippedClub]
    /// The active view of the course (2D or 3D).
    let renderer: GolfRenderer
    /// Exactly one of these is set, depending on the view mode.
    let scene2D: GolfGameScene?
    let scene3D: GolfScene3D?
    let meter = SwingMeterModel()

    @Published private(set) var holeIndex = 0
    @Published private(set) var phase: Phase = .intro
    @Published private(set) var strokes = 0
    @Published private(set) var scores: [HoleScore] = []
    @Published private(set) var selectedClub: ClubType = .driver
    @Published private(set) var lie: Terrain = .tee
    @Published private(set) var distanceToPin = 0.0
    @Published private(set) var targetDistance = 0.0
    @Published private(set) var playsLike = 0.0
    @Published private(set) var viewRotation = 0.0
    @Published private(set) var overview = false
    @Published private(set) var lastHoleTitle = ""
    @Published private(set) var finishedResult: RoundResult?
    @Published var banner: GameBanner?

    private(set) var ballPos = Vec2.zero
    private var previousPos = Vec2.zero
    private var aimTarget = Vec2.zero
    private var previewDirty = false
    private var rng = SeededRandom(seed: UInt64.random(in: 1...UInt64.max))

    init(course: GolfCourse, length: RoundLength, bag: [ClubType: EquippedClub], use3D: Bool) {
        self.course = course
        self.length = length
        self.holes = course.holes(for: length)
        self.bag = bag
        if use3D {
            let s = GolfScene3D()
            self.scene3D = s
            self.scene2D = nil
            self.renderer = s
        } else {
            let s = GolfGameScene(size: CGSize(width: 1024, height: 768))
            self.scene2D = s
            self.scene3D = nil
            self.renderer = s
        }
        self.renderer.attach(self)
    }

    // MARK: - Derived info for the HUD

    var hole: GolfHole { holes[holeIndex] }
    var currentClub: EquippedClub { bag[selectedClub] ?? EquippedClub(card: ClubCatalog.starter(for: selectedClub), level: 1) }
    var isPutting: Bool { selectedClub == .putter }
    var theme: CourseTheme { course.theme }

    var completedToPar: Int { scores.reduce(0) { $0 + $1.toPar } }
    var target: Int { course.target(for: length) }

    var rivalToParSoFar: Int {
        var total = 0
        for i in 0..<scores.count where i < holes.count {
            total += holes[i].botStrokes - holes[i].par
        }
        return total
    }

    func isClubAllowed(_ type: ClubType) -> Bool {
        if lie == .green { return type == .putter }
        if type == .putter { return lie == .fringe || (lie == .fairway && distanceToPin < 25) }
        return true
    }

    // MARK: - Round flow

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        loadHole(0)
    }

    private func loadHole(_ index: Int) {
        holeIndex = index
        strokes = 0
        let h = hole
        ballPos = h.tee
        previousPos = h.tee
        overview = false
        phase = .intro
        renderer.loadHole(h, theme: theme)
        renderer.placeBall(at: ballPos)
        renderer.playIntro { [weak self] in
            guard let self = self else { return }
            if self.phase == .intro {
                self.phase = .aiming
            }
        }
        prepareShot()
        phase = .intro
        let elevation = abs(h.greenElevation) >= 3 ? (h.greenElevation > 0 ? " · Uphill" : " · Downhill") : ""
        showBanner(GameBanner(title: "HOLE \(h.number) · PAR \(h.par)",
                              subtitle: "\(h.name) · \(h.yardage) yds\(elevation)", style: .neutral), duration: 2.4)
    }

    func skipIntro() {
        renderer.skipIntro()
    }

    private func prepareShot() {
        let h = hole
        lie = h.terrain(at: ballPos)
        if lie.isPenalty { lie = .rough }
        distanceToPin = ballPos.distance(to: h.cup)
        selectedClub = ShotAdvisor.suggestClub(bag: bag, lie: lie, hole: h, from: ballPos)
        aimTarget = ShotAdvisor.defaultTarget(club: currentClub, lie: lie, hole: h, from: ballPos)
        viewRotation = (aimTarget - ballPos).angle - Double.pi / 2
        configureMeter()
        refreshPreview()
        if phase != .intro {
            phase = .aiming
        }
    }

    private func configureMeter() {
        let club = currentClub
        let mods = club.modifiers(lie: lie, targetDistance: ballPos.distance(to: aimTarget))
        let windows = TimingWindows.make(forgiveness: club.stats.forgiveness, multiplier: mods.windowMultiplier)
        meter.configure(windows: windows, isPutt: isPutting, speed: club.meterSpeed)
    }

    func selectClub(_ type: ClubType) {
        guard phase == .aiming || phase == .intro, isClubAllowed(type), type != selectedClub else { return }
        selectedClub = type
        aimTarget = ShotAdvisor.defaultTarget(club: currentClub, lie: lie, hole: hole, from: ballPos)
        configureMeter()
        previewDirty = true
        Feedback.shared.play(.tick)
        Feedback.shared.impact(.light)
    }

    func dragAim(by delta: Vec2) {
        guard phase == .aiming else { return }
        let sensitivity = isPutting ? 0.5 : 1.0
        aimTarget = ShotAdvisor.clampTarget(aimTarget + delta * sensitivity, club: currentClub, lie: lie, hole: hole, from: ballPos)
        previewDirty = true
    }

    func aimDragEnded() {
        if previewDirty { refreshPreview() }
    }

    func resetAim() {
        guard phase == .aiming else { return }
        aimTarget = ShotAdvisor.defaultTarget(club: currentClub, lie: lie, hole: hole, from: ballPos)
        previewDirty = true
    }

    func toggleOverview() {
        overview.toggle()
        renderer.setOverview(overview)
    }

    /// Called every frame by the renderer.
    func tick(_ dt: Double) {
        if previewDirty && phase == .aiming {
            refreshPreview()
        }
        handle(meter.tick(dt))
    }

    private func refreshPreview() {
        previewDirty = false
        let h = hole
        let club = currentClub
        let from = ballPos
        let to = aimTarget
        targetDistance = from.distance(to: to)
        distanceToPin = from.distance(to: h.cup)
        let dir = (to - from).normalized
        let mods = club.modifiers(lie: lie, targetDistance: targetDistance)
        if isPutting {
            let speed = ShotSolver.puttSpeed(distance: targetDistance, hole: h, from: from, dir: dir)
            let start = BallState(pos: from, z: h.groundHeight(at: from), vel: dir * speed, vz: 0,
                                  backspin: 0, sideSpin: 0, phase: .rolling)
            let trace = BallSimulator.trace(hole: h, start: start, options: SimOptions(), sampleEvery: 0.04)
            renderer.setPreview(points: trace.points, landingIndex: nil, isPutt: true, visibleFraction: mods.puttPreviewFraction)
            playsLike = targetDistance
        } else {
            let angle = club.type.launchAngle
            let speed = ShotSolver.speed(toCarry: targetDistance, hole: h, from: from, dir: dir, launchAngleDeg: angle)
            let (v, vz) = ShotSolver.launch(dir: dir, speed: speed, launchAngleDeg: angle)
            var opts = SimOptions()
            opts.useTrees = false
            let start = BallState(pos: from, z: h.groundHeight(at: from), vel: v, vz: vz,
                                  backspin: mods.backspin, sideSpin: 0, phase: .flight)
            let trace = BallSimulator.trace(hole: h, start: start, options: opts, sampleEvery: 0.06)
            renderer.setPreview(points: trace.points, landingIndex: trace.landingIndex, isPutt: false, visibleFraction: 1)
            playsLike = ShotSolver.flatCarry(speed: speed, launchAngleDeg: angle)
        }
        if renderer.cameraFollowsAim && targetDistance > 0.05 {
            viewRotation = (to - from).angle - Double.pi / 2
        }
        renderer.setAim(from: from, to: to, rotation: viewRotation, isPutt: isPutting)
    }

    // MARK: - Swing input (from the HUD button)

    func swingPressed() {
        switch phase {
        case .intro:
            skipIntro()
        case .aiming:
            if overview { toggleOverview() }
            if previewDirty { refreshPreview() }
            phase = .swinging
            handle(meter.touchDown())
            Feedback.shared.impact(.light)
        case .swinging:
            handle(meter.touchDown())
        default:
            break
        }
    }

    func swingReleased() {
        guard phase == .swinging else { return }
        handle(meter.touchUp())
    }

    private func handle(_ event: SwingMeterState.Event) {
        switch event {
        case .none:
            break
        case .cancelled:
            phase = .aiming
            meter.reset()
        case .powerLocked:
            Feedback.shared.play(.swing)
        case let .completed(power, offset):
            execute(power: power, offset: offset)
        }
    }

    private func execute(power: Double, offset: Double?) {
        let h = hole
        let club = currentClub
        strokes += 1
        previousPos = ballPos
        let shot: ShotLaunch
        if isPutting {
            shot = ShotPlanner.putt(club: club, lie: lie, hole: h, from: ballPos, target: aimTarget, power: power, rng: &rng)
            showBanner(GameBanner(title: ShotPlanner.puttRating(power: power), subtitle: nil, style: abs(power - 1) < 0.08 ? .good : .neutral), duration: 1.0)
            Feedback.shared.play(.putt)
            Feedback.shared.impact(.light)
        } else {
            shot = ShotPlanner.fullSwing(club: club, lie: lie, hole: h, from: ballPos, target: aimTarget,
                                         power: power, offset: offset ?? 1.2, rng: &rng)
            if let outcome = shot.outcome {
                let style: GameBanner.Style
                switch outcome {
                case .perfect: style = .great
                case .great, .good: style = .good
                case .early, .late: style = .neutral
                case .poor: style = .bad
                }
                let powerText = "\(Int((power * 100).rounded()))% power"
                showBanner(GameBanner(title: outcome.title, subtitle: powerText, style: style), duration: 1.2)
                Feedback.shared.play(outcome == .perfect ? .perfect : .hit)
                Feedback.shared.impact(outcome == .perfect ? .heavy : .medium)
            }
        }
        phase = .ballMoving
        renderer.launch(shot)
    }

    // MARK: - Ball results

    func ballDidFinish(_ state: BallState) {
        let h = hole
        switch state.phase {
        case .holed:
            finishHole(pickedUp: false)
            return
        case .water:
            strokes += 1
            ballPos = h.dropPoint(entry: state.pos, from: previousPos)
            showBanner(GameBanner(title: theme.hazardName.uppercased(), subtitle: "Penalty +1 · Drop", style: .bad), duration: 1.6)
        case .outOfBounds:
            strokes += 1
            ballPos = previousPos
            showBanner(GameBanner(title: "OUT OF BOUNDS", subtitle: "Stroke and distance +1", style: .bad), duration: 1.6)
        default:
            ballPos = state.pos
        }

        if strokes >= ScoreName.maxStrokes(par: h.par) {
            finishHole(pickedUp: true)
            return
        }
        renderer.placeBall(at: ballPos)
        prepareShot()
    }

    private func finishHole(pickedUp: Bool) {
        let h = hole
        let holeStrokes = pickedUp ? ScoreName.maxStrokes(par: h.par) : strokes
        strokes = holeStrokes
        scores.append(HoleScore(par: h.par, strokes: holeStrokes))
        lastHoleTitle = pickedUp ? "PICKED UP" : ScoreName.name(strokes: holeStrokes, par: h.par)
        meter.reset()
        phase = .holeComplete
        if holeStrokes < h.par {
            Feedback.shared.play(.coin)
        }
    }

    func continueAfterHole() {
        guard phase == .holeComplete else { return }
        if holeIndex + 1 < holes.count {
            loadHole(holeIndex + 1)
        } else {
            finishedResult = RoundResult(courseIndex: course.index, courseID: course.id, courseName: course.name,
                                         length: length, difficulty: course.difficulty, target: target, scores: scores)
            phase = .roundComplete
        }
    }

    // MARK: - Banners

    private func showBanner(_ b: GameBanner, duration: Double) {
        banner = b
        let id = b.id
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            if self?.banner?.id == id {
                self?.banner = nil
            }
        }
    }
}
