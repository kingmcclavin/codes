import SceneKit
import SwiftUI
import UIKit

/// Small 3D point helper (SceneKit space: X right, Y up, Z toward the viewer at the tee).
struct P3 {
    var x: Double
    var y: Double
    var z: Double

    init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// World ground position + height -> SceneKit position.
    init(world p: Vec2, height: Double) {
        self.init(p.x, height, -p.y)
    }

    var scn: SCNVector3 { SCNVector3(x: Float(x), y: Float(y), z: Float(z)) }

    func distance(to o: P3) -> Double {
        let dx = x - o.x
        let dy = y - o.y
        let dz = z - o.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    static func lerp(_ a: P3, _ b: P3, _ t: Double) -> P3 {
        P3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
    }
}

/// Retains the 3D scene weakly so the display link never keeps it alive.
private final class DisplayLinkProxy: NSObject {
    weak var owner: GolfScene3D?

    init(owner: GolfScene3D) {
        self.owner = owner
    }

    @objc func step(_ link: CADisplayLink) {
        if let o = owner {
            o.frameTick(link)
        } else {
            link.invalidate()
        }
    }
}

/// The SceneKit 3D view of a hole. Game rules stay in RoundController; this class renders,
/// animates the ball with the same BallSimulator as 2D, drives the camera and turns drags into aim changes.
final class GolfScene3D: NSObject, GolfRenderer {
    weak var controller: RoundController?

    let scene = SCNScene()
    private(set) var view: SCNView?
    private let cameraNode = SCNNode()
    private let courseRoot = SCNNode()
    private let ballNode: SCNNode
    private let ballShadow: SCNNode
    private let cupNode: SCNNode
    private let flagNode = SCNNode()
    private let reticle = SCNNode()
    private var dots: [SCNNode] = []
    private var previewPoints: [Vec3] = []
    private var previewAlphas: [Double] = []

    private var hole: GolfHole?
    private var sim: BallSimulator?
    private var finishCountdown = 0.0
    private var trailTimer = 0.0
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var paused = false

    private enum Mode {
        case idle
        case intro
        case aiming
        case flight
        case overview
    }
    private var mode: Mode = .idle
    private var modeBeforeOverview: Mode = .aiming
    private var aimFrom = Vec2.zero
    private var aimTo = Vec2(0, 10)
    private var isPutt = false
    private var dragging = false
    private var introTime = 0.0
    private var introDone: (() -> Void)?
    private var flightDir = Vec2(0, 1)
    private var shotIsPutt = false
    private var landingOn = false
    private let swingRig = ClubSwingRig()
    /// A struck shot waiting for the club to reach the ball.
    private var pendingShot: ShotLaunch?

    private var ballGround = Vec2.zero
    private var ballZ = 0.0

    // Camera state (smoothed toward the targets every frame).
    private var eye = P3(0, 6, 12)
    private var look = P3(0, 0, -30)
    private var eyeTarget = P3(0, 6, 12)
    private var lookTarget = P3(0, 0, -30)
    private var stiffness = 3.0

    private static let fieldOfView = 55.0
    private static let ballRadius = 0.15
    private static let colorDot = UIColor.white

    var cameraFollowsAim: Bool { true }

    override init() {
        let ballGeo = SCNSphere(radius: CGFloat(GolfScene3D.ballRadius))
        ballGeo.segmentCount = 18
        let ballMat = SCNMaterial()
        ballMat.diffuse.contents = UIColor.white
        ballMat.lightingModel = .blinn
        ballMat.emission.contents = UIColor(white: 0.25, alpha: 1)
        ballGeo.materials = [ballMat]
        ballNode = SCNNode(geometry: ballGeo)

        let shadowGeo = SCNCylinder(radius: CGFloat(GolfScene3D.ballRadius * 1.1), height: 0.01)
        shadowGeo.materials = [Course3DBuilder.material(UIColor.black.withAlphaComponent(0.4), lit: false)]
        ballShadow = SCNNode(geometry: shadowGeo)

        let cupGeo = SCNCylinder(radius: CGFloat(Physics.cupRadius), height: 0.02)
        cupGeo.materials = [Course3DBuilder.material(UIColor(white: 0.05, alpha: 1), lit: false)]
        cupNode = SCNNode(geometry: cupGeo)

        super.init()
        setUpScene()
    }

    deinit {
        displayLink?.invalidate()
    }

    func attach(_ controller: RoundController) {
        self.controller = controller
    }

    // MARK: - Scene setup

    private func setUpScene() {
        let camera = SCNCamera()
        camera.zNear = 0.1
        camera.zFar = 4000
        camera.fieldOfView = CGFloat(GolfScene3D.fieldOfView)
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(white: 0.45, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.color = UIColor(white: 0.7, alpha: 1)
        sun.eulerAngles = SCNVector3(x: -0.95, y: 0.6, z: 0)
        scene.rootNode.addChildNode(sun)

        scene.fogStartDistance = 220
        scene.fogEndDistance = 900

        scene.rootNode.addChildNode(courseRoot)
        scene.rootNode.addChildNode(ballShadow)
        scene.rootNode.addChildNode(ballNode)
        scene.rootNode.addChildNode(cupNode)
        scene.rootNode.addChildNode(swingRig.root)

        let pole = SCNCylinder(radius: 0.035, height: 3.0)
        pole.materials = [Course3DBuilder.material(.white)]
        let poleNode = SCNNode(geometry: pole)
        poleNode.position = SCNVector3(x: 0, y: 1.5, z: 0)
        flagNode.addChildNode(poleNode)
        let cloth = SCNBox(width: 1.0, height: 0.6, length: 0.02, chamferRadius: 0)
        cloth.materials = [Course3DBuilder.material(UIColor(red: 0.95, green: 0.2, blue: 0.25, alpha: 1))]
        let clothNode = SCNNode(geometry: cloth)
        clothNode.position = SCNVector3(x: 0.5, y: 2.68, z: 0)
        clothNode.runAction(SCNAction.repeatForever(SCNAction.sequence([
            SCNAction.rotateBy(x: 0, y: 0.35, z: 0, duration: 0.7),
            SCNAction.rotateBy(x: 0, y: -0.35, z: 0, duration: 0.7)
        ])))
        flagNode.addChildNode(clothNode)
        scene.rootNode.addChildNode(flagNode)

        let yellow = UIColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        let ring = SCNTorus(ringRadius: 1.0, pipeRadius: 0.08)
        ring.materials = [Course3DBuilder.material(yellow, lit: false)]
        reticle.addChildNode(SCNNode(geometry: ring))
        let beam = SCNCylinder(radius: 0.06, height: 6)
        let beamMat = Course3DBuilder.material(yellow.withAlphaComponent(0.45), lit: false)
        beam.materials = [beamMat]
        let beamNode = SCNNode(geometry: beam)
        beamNode.position = SCNVector3(x: 0, y: 3, z: 0)
        reticle.addChildNode(beamNode)
        reticle.isHidden = true
        scene.rootNode.addChildNode(reticle)

        let dotGeo = SCNSphere(radius: 0.13)
        dotGeo.segmentCount = 8
        dotGeo.materials = [Course3DBuilder.material(GolfScene3D.colorDot, lit: false)]
        for _ in 0..<90 {
            let d = SCNNode(geometry: dotGeo)
            d.isHidden = true
            scene.rootNode.addChildNode(d)
            dots.append(d)
        }
    }

    /// Creates (once) the SCNView that SwiftUI hosts.
    func makeView() -> SCNView {
        if let v = view { return v }
        let v = SCNView(frame: .zero)
        v.scene = scene
        v.pointOfView = cameraNode
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        v.rendersContinuously = true
        v.isPlaying = true
        v.backgroundColor = .black
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        v.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        v.addGestureRecognizer(tap)
        view = v
        startLoop()
        return v
    }

    func setPaused(_ p: Bool) {
        paused = p
        view?.isPlaying = !p
    }

    private func startLoop() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: DisplayLinkProxy(owner: self), selector: #selector(DisplayLinkProxy.step(_:)))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func skyImage(_ theme: CourseTheme) -> UIImage {
        let size = CGSize(width: 8, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let colors = [theme.skyTop.ui.cgColor, theme.skyBottom.ui.cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
    }

    // MARK: - GolfRenderer

    func loadHole(_ hole: GolfHole, theme: CourseTheme) {
        self.hole = hole
        for child in courseRoot.childNodes {
            child.removeFromParentNode()
        }
        courseRoot.addChildNode(Course3DBuilder.build(hole: hole, theme: theme))
        scene.background.contents = skyImage(theme)
        scene.fogColor = theme.skyBottom.ui
        let cupGround = hole.groundHeight(at: hole.cup)
        cupNode.position = P3(world: hole.cup, height: cupGround + 0.012).scn
        flagNode.position = P3(world: hole.cup, height: cupGround).scn
        sim = nil
        pendingShot = nil
        swingRig.hide()
        hidePreview()
        reticle.isHidden = true
    }

    func placeBall(at p: Vec2) {
        sim = nil
        ballGround = p
        ballZ = hole?.groundHeight(at: p) ?? 0
        ballNode.isHidden = false
        ballShadow.isHidden = false
        placeClub()
    }

    // MARK: - Club

    private func syncClubModel() -> Bool {
        guard let c = controller else { return false }
        let club = c.currentClub
        return swingRig.setClub(type: club.type, key: club.card.id, accent: club.card.rarity.color.ui)
    }

    /// Puts the club at address behind the resting ball, aimed at the target.
    private func placeClub() {
        guard let hole = hole, sim == nil, pendingShot == nil else { return }
        _ = syncClubModel()
        swingRig.place(ballGround: ballGround, groundHeight: hole.groundHeight(at: ballGround), aimDir: aimTo - aimFrom,
                       ballRadius: GolfScene3D.ballRadius)
    }

    private func outcomeColor(_ outcome: SwingOutcome?) -> UIColor {
        guard let o = outcome else { return UIColor.white }
        switch o {
        case .perfect: return UIColor(red: 0.2, green: 0.95, blue: 0.4, alpha: 1)
        case .great: return UIColor(red: 0.65, green: 1, blue: 0.5, alpha: 1)
        case .good: return UIColor(red: 1, green: 0.9, blue: 0.3, alpha: 1)
        case .early, .late: return UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 1)
        case .poor: return UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
        }
    }

    func playIntro(completion: @escaping () -> Void) {
        guard let hole = hole else {
            completion()
            return
        }
        let axis = (hole.greenCenter - hole.tee).normalized
        let gElev = hole.groundHeight(at: hole.greenCenter)
        eye = P3(world: hole.greenCenter - axis * 38 + axis.leftPerp * 12, height: gElev + 16)
        look = P3(world: hole.greenCenter, height: gElev)
        eyeTarget = eye
        lookTarget = look
        stiffness = 1.3
        introTime = 0
        introDone = completion
        mode = .intro
        reticle.isHidden = true
        hidePreview()
    }

    func skipIntro() {
        if mode == .intro { introTime = 99 }
    }

    func setAim(from: Vec2, to: Vec2, rotation: Double, isPutt: Bool) {
        aimFrom = from
        aimTo = to
        self.isPutt = isPutt
        if mode != .overview && mode != .intro {
            mode = .aiming
            stiffness = 3.0
        }
        reticle.isHidden = false
        placeClub()
    }

    func setPreview(points: [Vec3], landingIndex: Int?, isPutt: Bool, visibleFraction: Double) {
        previewPoints = []
        previewAlphas = []
        guard points.count > 1 else { return }
        if isPutt {
            let count = max(2, Int(Double(points.count) * visibleFraction))
            for (i, p) in points.prefix(count).enumerated() where i % 2 == 0 {
                previewPoints.append(p)
                previewAlphas.append(0.85 * (1 - Double(i) / Double(count)))
            }
        } else {
            let landing = landingIndex ?? (points.count - 1)
            for (i, p) in points.enumerated() {
                if i <= landing {
                    if i % 2 == 0 || i == landing {
                        previewPoints.append(p)
                        previewAlphas.append(0.9)
                    }
                } else if i % 3 == 0 {
                    previewPoints.append(p)
                    previewAlphas.append(0.4)
                }
            }
        }
        if previewPoints.count > dots.count {
            previewPoints = Array(previewPoints.prefix(dots.count))
            previewAlphas = Array(previewAlphas.prefix(dots.count))
        }
    }

    func hidePreview() {
        previewPoints = []
        previewAlphas = []
        for d in dots { d.isHidden = true }
    }

    func setLandingView(_ on: Bool) {
        landingOn = on
    }

    func setOverview(_ on: Bool) {
        if on {
            if mode != .overview { modeBeforeOverview = mode }
            mode = .overview
            stiffness = 2.0
        } else if mode == .overview {
            mode = modeBeforeOverview
            stiffness = 3.0
        }
    }

    func launch(_ shot: ShotLaunch) {
        guard hole != nil else { return }
        hidePreview()
        reticle.isHidden = true
        // Swing the club first; the ball leaves at impact (see frameTick).
        if swingRig.startDownswing(sideSpin: shot.state.sideSpin, outcomeColor: outcomeColor(shot.outcome)) {
            pendingShot = shot
        } else {
            beginFlight(shot)
        }
        if mode != .overview {
            mode = .flight
            stiffness = 4.0
        }
        let v = shot.state.vel
        flightDir = v.length > 0.01 ? v.normalized : (aimTo - aimFrom).normalized
        shotIsPutt = shot.state.phase == .rolling
    }

    private func beginFlight(_ shot: ShotLaunch) {
        guard let hole = hole else { return }
        sim = BallSimulator(hole: hole, state: shot.state, options: shot.options)
        finishCountdown = 0
        trailTimer = 0
    }

    // MARK: - Frame loop

    fileprivate func frameTick(_ link: CADisplayLink) {
        let now = link.timestamp
        var dt = lastTimestamp == 0 ? 1.0 / 60.0 : now - lastTimestamp
        lastTimestamp = now
        if paused { return }
        dt = dt.clamped(0, 1.0 / 20.0)
        controller?.tick(dt)
        if swingRig.isAtAddress && syncClubModel() {
            placeClub()
        }
        swingRig.update(dt, meter: controller?.meter.state, trailParent: scene.rootNode)
        if swingRig.takeImpact(), let shot = pendingShot {
            pendingShot = nil
            beginFlight(shot)
            burst(at: P3(world: ballGround, height: ballZ + 0.1), color: UIColor.white, count: 8, size: 0.05, spread: 0.6)
        }
        stepBall(dt)
        updateCamera(dt)
        layoutDynamicNodes()
    }

    private func stepBall(_ dt: Double) {
        guard var s = sim else { return }
        if !s.isFinished {
            let speedUp = s.state.phase == .flight ? 1.5 : 1.3
            s.advance(dt * speedUp)
            for e in s.popEvents() { handle(e) }
            ballGround = s.state.pos
            ballZ = s.state.z
            if s.state.phase == .flight {
                trailTimer += dt
                if trailTimer > 0.03 {
                    trailTimer = 0
                    spawnTrail()
                }
            }
            if s.isFinished {
                finishCountdown = s.state.phase == .holed ? 1.4 : 0.8
            }
            sim = s
        } else {
            finishCountdown -= dt
            if finishCountdown <= 0 {
                sim = nil
                controller?.ballDidFinish(s.state)
            }
        }
    }

    private func groundPoint(_ p: Vec2, lift: Double = 0) -> P3 {
        P3(world: p, height: (hole?.groundHeight(at: p) ?? 0) + lift)
    }

    private func handle(_ e: SimEvent) {
        switch e {
        case let .landed(t, p):
            if t == .sand {
                burst(at: groundPoint(p, lift: 0.2), color: UIColor(red: 0.95, green: 0.86, blue: 0.62, alpha: 1), count: 16, size: 0.18, spread: 2.5)
            } else {
                burst(at: groundPoint(p, lift: 0.1), color: UIColor(red: 0.55, green: 0.85, blue: 0.45, alpha: 1), count: 8, size: 0.1, spread: 1.2)
            }
            Feedback.shared.play(.land)
            Feedback.shared.impact(.light)
        case let .treeHit(p):
            burst(at: P3(world: p, height: ballZ), color: UIColor(red: 0.3, green: 0.6, blue: 0.25, alpha: 1), count: 14, size: 0.25, spread: 3)
            Feedback.shared.play(.land)
            Feedback.shared.impact(.medium)
        case let .splash(p):
            burst(at: groundPoint(p, lift: 0.1), color: UIColor(red: 0.7, green: 0.9, blue: 1, alpha: 1), count: 22, size: 0.22, spread: 3.5)
            ballNode.isHidden = true
            ballShadow.isHidden = true
            Feedback.shared.play(.splash)
            Feedback.shared.warning()
        case .outOfBounds:
            Feedback.shared.warning()
        case .lipOut:
            Feedback.shared.play(.tick)
            Feedback.shared.impact(.rigid)
        case let .holed(p):
            ballNode.isHidden = true
            ballShadow.isHidden = true
            confetti(at: groundPoint(p, lift: 0.3))
            Feedback.shared.play(.cup)
            Feedback.shared.success()
        }
    }

    // MARK: - Camera

    private func updateCamera(_ dt: Double) {
        guard let hole = hole else { return }
        switch mode {
        case .idle:
            break
        case .intro:
            introTime += dt
            if introTime > 1.0 {
                aimingPose(hole)
            }
            if introTime > 2.8 {
                mode = .aiming
                stiffness = 3.0
                let done = introDone
                introDone = nil
                done?()
            }
        case .aiming:
            if landingOn {
                landingPose(hole)
            } else {
                aimingPose(hole)
            }
        case .flight:
            flightPose(hole)
        case .overview:
            overviewPose(hole)
        }
        let k = 1 - exp(-stiffness * dt)
        let kl = 1 - exp(-stiffness * 1.8 * dt)
        eye = P3.lerp(eye, eyeTarget, k)
        look = P3.lerp(look, lookTarget, kl)
        cameraNode.position = eye.scn
        // Always use world "up" so the camera never rolls sideways as the aim turns.
        cameraNode.look(at: look.scn,
                        up: SCNVector3(x: 0, y: 1, z: 0),
                        localFront: SCNVector3(x: 0, y: 0, z: -1))
    }

    /// Behind the ball, looking down the aim line, with the ball a little below screen centre.
    private func aimingPose(_ hole: GolfHole) {
        let toTarget = aimTo - aimFrom
        let f = toTarget.length > 0.01 ? toTarget.normalized : (hole.cup - aimFrom).normalized
        let g = hole.groundHeight(at: aimFrom)
        let back = isPutt ? 5.0 : 12.0
        let height = isPutt ? 2.4 : 6.0
        let ballBelowCentre = isPutt ? 0.2 : 0.28
        let ballAngle = atan(height / back)
        let half = degreesToRadians(GolfScene3D.fieldOfView / 2)
        let pitch = ballAngle - atan(ballBelowCentre * tan(half))
        eyeTarget = P3(world: aimFrom - f * back, height: g + height)
        // Point 30 yards along the view direction, pitched down by `pitch`.
        let lookGround = aimFrom - f * back + f * (30 * cos(pitch))
        lookTarget = P3(world: lookGround, height: g + height - 30 * sin(pitch))
    }

    /// Hovers above and behind the aim target so the landing area is easy to read.
    private func landingPose(_ hole: GolfHole) {
        let toTarget = aimTo - aimFrom
        let f = toTarget.length > 0.01 ? toTarget.normalized : (hole.cup - aimFrom).normalized
        let g = hole.groundHeight(at: aimTo)
        let back = isPutt ? 5.0 : 26.0
        let height = isPutt ? 6.0 : 24.0
        eyeTarget = P3(world: aimTo - f * back, height: g + height)
        lookTarget = P3(world: aimTo + f * (isPutt ? 0.5 : 4), height: g)
    }

    /// Chase camera that trails the ball along the shot line.
    private func flightPose(_ hole: GolfHole) {
        let g = hole.groundHeight(at: ballGround)
        let back = shotIsPutt ? 4.0 : 13.0
        let minHeight = shotIsPutt ? 1.6 : 4.5
        eyeTarget = P3(world: ballGround - flightDir * back, height: max(g + minHeight, ballZ * 0.6 + minHeight))
        lookTarget = P3(world: ballGround, height: ballZ)
    }

    private func overviewPose(_ hole: GolfHole) {
        let axisV = hole.greenCenter - hole.tee
        let axis = axisV.normalized
        let length = max(80, axisV.length)
        let centre = hole.tee + axisV * 0.55
        eyeTarget = P3(world: hole.tee - axis * (length * 0.2), height: length * 0.55)
        lookTarget = P3(world: centre, height: 0)
    }

    // MARK: - Per-frame node layout

    private func layoutDynamicNodes() {
        guard let hole = hole else { return }
        let ballPos = P3(world: ballGround, height: ballZ + GolfScene3D.ballRadius)
        let s = max(1.0, eye.distance(to: ballPos) / 28)
        ballNode.position = P3(world: ballGround, height: ballZ + GolfScene3D.ballRadius * s).scn
        ballNode.scale = SCNVector3(x: Float(s), y: Float(s), z: Float(s))
        let ground = hole.groundHeight(at: ballGround)
        let h = max(0, ballZ - ground)
        ballShadow.position = P3(world: ballGround, height: ground + 0.02).scn
        ballShadow.scale = SCNVector3(x: Float(s), y: 1, z: Float(s))
        ballShadow.opacity = CGFloat(max(0.15, 1 - h / 30))

        let flagScale = max(1.0, eye.distance(to: P3(world: hole.cup, height: 0)) / 70)
        flagNode.scale = SCNVector3(x: Float(flagScale), y: Float(flagScale), z: Float(flagScale))

        if !reticle.isHidden {
            let rp = groundPoint(aimTo, lift: 0.05)
            let rs = max(isPutt ? 0.25 : 0.8, eye.distance(to: rp) * 0.022)
            reticle.position = rp.scn
            reticle.scale = SCNVector3(x: Float(rs), y: Float(isPutt ? rs * 0.3 : rs), z: Float(rs))
        }

        for (i, d) in dots.enumerated() {
            if i < previewPoints.count {
                let p = previewPoints[i]
                let pos = groundPoint(p.ground, lift: p.h + 0.12)
                let ds = max(0.6, eye.distance(to: pos) / 30)
                d.isHidden = false
                d.position = pos.scn
                d.scale = SCNVector3(x: Float(ds), y: Float(ds), z: Float(ds))
                d.opacity = CGFloat(previewAlphas[i])
            } else if !d.isHidden {
                d.isHidden = true
            }
        }
    }

    // MARK: - Effects

    private func spawnTrail() {
        let geo = SCNSphere(radius: 0.1)
        geo.segmentCount = 6
        geo.materials = [Course3DBuilder.material(UIColor.white.withAlphaComponent(0.7), lit: false)]
        let n = SCNNode(geometry: geo)
        n.position = ballNode.position
        n.scale = ballNode.scale
        scene.rootNode.addChildNode(n)
        n.runAction(SCNAction.sequence([
            SCNAction.group([SCNAction.fadeOut(duration: 0.7), SCNAction.scale(by: 0.3, duration: 0.7)]),
            SCNAction.removeFromParentNode()
        ]))
    }

    private func burst(at p: P3, color: UIColor, count: Int, size: Double, spread: Double) {
        let geo = SCNSphere(radius: CGFloat(size))
        geo.segmentCount = 6
        geo.materials = [Course3DBuilder.material(color)]
        for i in 0..<count {
            let n = SCNNode(geometry: geo)
            n.position = p.scn
            scene.rootNode.addChildNode(n)
            let a = Double(i) / Double(count) * 2 * Double.pi + Double.random(in: -0.3...0.3)
            let r = spread * Double.random(in: 0.5...1)
            let up = spread * Double.random(in: 0.4...1)
            let move = SCNAction.moveBy(x: CGFloat(cos(a) * r), y: CGFloat(up), z: CGFloat(sin(a) * r), duration: 0.5)
            move.timingMode = .easeOut
            n.runAction(SCNAction.sequence([
                SCNAction.group([move, SCNAction.fadeOut(duration: 0.6)]),
                SCNAction.removeFromParentNode()
            ]))
        }
    }

    private func confetti(at p: P3) {
        let colors: [UIColor] = [.systemYellow, .systemPink, .systemTeal, .white, .systemOrange, .systemGreen]
        for i in 0..<40 {
            let box = SCNBox(width: 0.12, height: 0.2, length: 0.02, chamferRadius: 0)
            box.materials = [Course3DBuilder.material(colors[i % colors.count], lit: false)]
            let n = SCNNode(geometry: box)
            n.position = p.scn
            scene.rootNode.addChildNode(n)
            let a = Double.random(in: 0...(2 * Double.pi))
            let r = Double.random(in: 0.5...2.5)
            let rise = SCNAction.moveBy(x: CGFloat(cos(a) * r), y: CGFloat(Double.random(in: 2...4)), z: CGFloat(sin(a) * r), duration: 0.6)
            rise.timingMode = .easeOut
            let fall = SCNAction.moveBy(x: 0, y: -2, z: 0, duration: 0.9)
            fall.timingMode = .easeIn
            n.runAction(SCNAction.sequence([
                SCNAction.group([
                    SCNAction.sequence([rise, fall]),
                    SCNAction.rotateBy(x: CGFloat.random(in: -6...6), y: CGFloat.random(in: -6...6), z: 0, duration: 1.5),
                    SCNAction.sequence([SCNAction.wait(duration: 1.0), SCNAction.fadeOut(duration: 0.5)])
                ]),
                SCNAction.removeFromParentNode()
            ]))
        }
    }

    // MARK: - Touch: drag left/right to aim, up/down to change distance

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard let v = view else { return }
        switch g.state {
        case .began:
            dragging = true
            if mode == .intro { skipIntro() }
        case .changed:
            let t = g.translation(in: v)
            g.setTranslation(.zero, in: v)
            let toTarget = aimTo - aimFrom
            let dist = max(1, toTarget.length)
            let f = toTarget.length > 0.01 ? toTarget.normalized : Vec2(0, 1)
            let lateral = Double(t.x) * 0.0016 * max(dist, 10)
            let forward = -Double(t.y) * (isPutt ? 0.03 : 0.0035 * max(dist, 25))
            controller?.dragAim(by: f.rightPerp * lateral + f * forward)
        case .ended, .cancelled, .failed:
            dragging = false
            controller?.aimDragEnded()
        default:
            break
        }
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        if mode == .intro { skipIntro() }
    }
}

/// Hosts the SceneKit view inside SwiftUI.
struct Golf3DContainer: UIViewRepresentable {
    let renderer: GolfScene3D
    let paused: Bool

    func makeUIView(context: Context) -> SCNView {
        renderer.makeView()
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        renderer.setPaused(paused)
    }
}
