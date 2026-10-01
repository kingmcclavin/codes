import SpriteKit
import UIKit

/// The SpriteKit layer: draws the hole, animates the ball and camera, and forwards aim drags.
/// Game rules live in RoundController; this class only renders and simulates the moving ball.
final class GolfGameScene: SKScene {
    weak var controller: RoundController?

    /// Points of the screen covered by the SwiftUI HUD (used to frame the camera).
    var topInset: Double = 150
    var bottomInset: Double = 290

    private let world = SKNode()
    private let cam = SKCameraNode()
    private var courseNode: SKNode?
    private let ball = SKShapeNode(circleOfRadius: 1)
    private let ballShadow = SKShapeNode(circleOfRadius: 1)
    private let cupNode = SKShapeNode(circleOfRadius: 1)
    private let flag = SKNode()
    private let reticle = SKNode()
    private var dots: [SKShapeNode] = []
    private var previewPoints: [Vec3] = []
    private var previewAlphas: [CGFloat] = []

    private var hole: GolfHole?
    private var sim: BallSimulator?
    private var finishCountdown = 0.0
    private var lastUpdate: TimeInterval = 0
    private var trailTimer = 0.0

    private var rig = CameraRig()
    private enum CameraMode {
        case idle
        case intro
        case aiming
        case flight
        case overview
    }
    private var cameraMode: CameraMode = .idle
    private var modeBeforeOverview: CameraMode = .aiming
    private var aimFrom = Vec2.zero
    private var aimTo = Vec2.zero
    private var aimRotation = 0.0
    private var isPuttView = false
    private var isDragging = false
    private var landingOn = false
    private var introTime = 0.0
    private var introDone: (() -> Void)?

    private var ballGround = Vec2.zero
    private var ballHeight = 0.0

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.17, green: 0.35, blue: 0.17, alpha: 1)
        addChild(world)
        addChild(cam)
        camera = cam
        buildDynamicNodes()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = false
    }

    // MARK: - Setup

    private func buildDynamicNodes() {
        ballShadow.fillColor = UIColor.black.withAlphaComponent(0.35)
        ballShadow.strokeColor = .clear
        ballShadow.zPosition = 49
        world.addChild(ballShadow)

        ball.fillColor = .white
        ball.strokeColor = UIColor(white: 0.75, alpha: 1)
        ball.lineWidth = 0.15
        ball.zPosition = 60
        world.addChild(ball)

        cupNode.fillColor = UIColor(white: 0.08, alpha: 1)
        cupNode.strokeColor = UIColor(white: 1, alpha: 0.7)
        cupNode.lineWidth = 0.12
        cupNode.zPosition = 10
        world.addChild(cupNode)

        let polePath = CGMutablePath()
        polePath.move(to: .zero)
        polePath.addLine(to: CGPoint(x: 0, y: 42))
        let pole = SKShapeNode(path: polePath)
        pole.strokeColor = .white
        pole.lineWidth = 1.6
        flag.addChild(pole)
        let clothPath = CGMutablePath()
        clothPath.move(to: CGPoint(x: 0, y: 42))
        clothPath.addLine(to: CGPoint(x: 18, y: 36))
        clothPath.addLine(to: CGPoint(x: 0, y: 30))
        clothPath.closeSubpath()
        let cloth = SKShapeNode(path: clothPath)
        cloth.fillColor = UIColor(red: 0.95, green: 0.2, blue: 0.25, alpha: 1)
        cloth.strokeColor = .clear
        flag.addChild(cloth)
        cloth.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scaleX(to: 0.85, duration: 0.6),
            SKAction.scaleX(to: 1.0, duration: 0.6)
        ])))
        flag.zPosition = 55
        world.addChild(flag)

        let ring = SKShapeNode(circleOfRadius: 13)
        ring.strokeColor = UIColor.white
        ring.lineWidth = 2
        ring.fillColor = UIColor.white.withAlphaComponent(0.12)
        reticle.addChild(ring)
        let inner = SKShapeNode(circleOfRadius: 3)
        inner.fillColor = UIColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        inner.strokeColor = .clear
        reticle.addChild(inner)
        for a in 0..<4 {
            let tick = CGMutablePath()
            let ang = CGFloat(a) * .pi / 2
            tick.move(to: CGPoint(x: cos(ang) * 9, y: sin(ang) * 9))
            tick.addLine(to: CGPoint(x: cos(ang) * 18, y: sin(ang) * 18))
            let t = SKShapeNode(path: tick)
            t.strokeColor = .white
            t.lineWidth = 2
            reticle.addChild(t)
        }
        reticle.zPosition = 58
        reticle.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.6, duration: 0.7),
            SKAction.fadeAlpha(to: 1.0, duration: 0.7)
        ])))
        world.addChild(reticle)

        for _ in 0..<110 {
            let d = SKShapeNode(circleOfRadius: 1)
            d.fillColor = .white
            d.strokeColor = .clear
            d.zPosition = 57
            d.isHidden = true
            world.addChild(d)
            dots.append(d)
        }
    }

    // MARK: - API used by RoundController

    func loadHole(_ hole: GolfHole, theme: CourseTheme) {
        self.hole = hole
        courseNode?.removeFromParent()
        let node = CourseRenderer.build(hole: hole, theme: theme)
        world.addChild(node)
        courseNode = node
        cupNode.position = hole.cup.cg
        flag.position = hole.cup.cg
        sim = nil
        hidePreview()
        reticle.isHidden = true
    }

    func placeBall(at p: Vec2) {
        sim = nil
        ballGround = p
        ballHeight = 0
        ball.isHidden = false
        ballShadow.isHidden = false
    }

    /// Fly over the hole from the green back to the tee, then call `completion`.
    func playIntro(completion: @escaping () -> Void) {
        guard let hole = hole else {
            completion()
            return
        }
        let rot = (hole.greenCenter - hole.tee).angle - Double.pi / 2
        rig.frame(points: [hole.greenCenter, hole.greenCenter + Vec2(angle: rot + Double.pi / 2) * 30],
                  rotation: rot, viewWidth: Double(size.width), viewHeight: Double(size.height),
                  topInset: topInset, bottomInset: bottomInset, padding: 20, minScale: 0.05)
        rig.snap()
        rig.frame(points: [hole.tee, hole.greenCenter], rotation: rot, viewWidth: Double(size.width), viewHeight: Double(size.height),
                  topInset: topInset, bottomInset: bottomInset, padding: 25, minScale: 0.1)
        rig.stiffness = 1.4
        introTime = 0
        introDone = completion
        cameraMode = .intro
        reticle.isHidden = true
        hidePreview()
    }

    func skipIntro() {
        if cameraMode == .intro {
            introTime = 99
        }
    }

    func setAim(from: Vec2, to: Vec2, rotation: Double, isPutt: Bool) {
        aimFrom = from
        aimTo = to
        aimRotation = rotation
        isPuttView = isPutt
        if cameraMode != .overview && cameraMode != .intro {
            cameraMode = .aiming
        }
        reticle.isHidden = false
        reticle.position = to.cg
    }

    func setPreview(points: [Vec3], landingIndex: Int?, isPutt: Bool, visibleFraction: Double) {
        previewPoints = []
        previewAlphas = []
        guard points.count > 1 else { return }
        if isPutt {
            let count = max(2, Int(Double(points.count) * visibleFraction))
            let pts = Array(points.prefix(count))
            for (i, p) in pts.enumerated() where i % 2 == 0 {
                previewPoints.append(p)
                previewAlphas.append(CGFloat(0.8 * (1 - Double(i) / Double(count))))
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
                    previewAlphas.append(0.35)
                }
            }
        }
        if previewPoints.count > dots.count {
            previewPoints = Array(previewPoints.prefix(dots.count))
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
            if cameraMode != .overview { modeBeforeOverview = cameraMode }
            cameraMode = .overview
        } else if cameraMode == .overview {
            cameraMode = modeBeforeOverview
        }
    }

    func launch(_ shot: ShotLaunch) {
        guard let hole = hole else { return }
        sim = BallSimulator(hole: hole, state: shot.state, options: shot.options)
        finishCountdown = 0
        hidePreview()
        reticle.isHidden = true
        rig.stiffness = 2.5
        if cameraMode != .overview { cameraMode = .flight }
        trailTimer = 0
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        var dt = lastUpdate == 0 ? 1.0 / 60.0 : currentTime - lastUpdate
        lastUpdate = currentTime
        dt = dt.clamped(0, 1.0 / 20.0)
        controller?.tick(dt)
        stepBall(dt)
        updateCamera(dt)
        layoutScreenSpaceNodes()
    }

    private func stepBall(_ dt: Double) {
        guard var s = sim else { return }
        if !s.isFinished {
            let speedUp = s.state.phase == .flight ? 1.6 : 1.35
            s.advance(dt * speedUp)
            for e in s.popEvents() { handle(e) }
            ballGround = s.state.pos
            ballHeight = s.heightAboveGround
            if s.state.phase == .flight {
                trailTimer += dt
                if trailTimer > 0.035 {
                    trailTimer = 0
                    spawnTrail()
                }
            }
            if s.isFinished {
                finishCountdown = s.state.phase == .holed ? 1.3 : 0.7
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

    private func handle(_ e: SimEvent) {
        switch e {
        case let .landed(t, p):
            if t == .sand {
                burst(at: p, color: UIColor(red: 0.95, green: 0.86, blue: 0.62, alpha: 1), count: 14, spread: 26)
            } else {
                burst(at: p, color: UIColor(white: 1, alpha: 0.7), count: 6, spread: 14)
            }
            Feedback.shared.play(.land)
            Feedback.shared.impact(.light)
        case let .treeHit(p):
            burst(at: p, color: UIColor(red: 0.3, green: 0.6, blue: 0.25, alpha: 1), count: 12, spread: 24)
            Feedback.shared.play(.land)
            Feedback.shared.impact(.medium)
        case let .splash(p):
            burst(at: p, color: UIColor(red: 0.6, green: 0.85, blue: 1, alpha: 1), count: 18, spread: 32)
            ripple(at: p)
            ball.isHidden = true
            ballShadow.isHidden = true
            Feedback.shared.play(.splash)
            Feedback.shared.warning()
        case .outOfBounds:
            Feedback.shared.warning()
        case .lipOut:
            Feedback.shared.play(.tick)
            Feedback.shared.impact(.rigid)
        case let .holed(p):
            ball.isHidden = true
            ballShadow.isHidden = true
            confetti(at: p)
            Feedback.shared.play(.cup)
            Feedback.shared.success()
        }
    }

    private func updateCamera(_ dt: Double) {
        let w = Double(size.width)
        let h = Double(size.height)
        switch cameraMode {
        case .idle:
            break
        case .intro:
            introTime += dt
            if introTime > 2.6 {
                cameraMode = .aiming
                rig.stiffness = 3.5
                let done = introDone
                introDone = nil
                done?()
            }
        case .aiming:
            if !isDragging {
                if landingOn {
                    // Close-up of the landing area around the target.
                    rig.frame(points: [aimTo], rotation: aimRotation, viewWidth: w, viewHeight: h,
                              topInset: topInset, bottomInset: bottomInset,
                              padding: isPuttView ? 4 : 30, minScale: isPuttView ? 0.02 : 0.05)
                } else {
                    var pts = [aimFrom, aimTo]
                    if isPuttView, let hole = hole { pts.append(hole.cup) }
                    rig.frame(points: pts, rotation: aimRotation, viewWidth: w, viewHeight: h,
                              topInset: topInset, bottomInset: bottomInset,
                              padding: isPuttView ? 3 : 18, minScale: isPuttView ? 0.03 : 0.1)
                }
            }
        case .flight:
            let rolling = sim?.state.phase == .rolling
            var pts = [ballGround, aimTo]
            if rolling { pts = [ballGround] + (isPuttView ? [aimTo] : []) }
            rig.frame(points: pts, rotation: aimRotation, viewWidth: w, viewHeight: h,
                      topInset: topInset, bottomInset: bottomInset,
                      padding: isPuttView ? 4 : 22, minScale: isPuttView ? 0.03 : (rolling ? 0.06 : 0.1))
        case .overview:
            if let hole = hole {
                let pts = [hole.tee, hole.greenCenter, ballGround] + hole.fairways.flatMap { $0.points }
                let rot = (hole.greenCenter - hole.tee).angle - Double.pi / 2
                rig.frame(points: pts, rotation: rot, viewWidth: w, viewHeight: h,
                          topInset: topInset, bottomInset: bottomInset, padding: 30, minScale: 0.1)
            }
        }
        rig.update(dt)
        cam.position = rig.position.cg
        cam.setScale(CGFloat(rig.scale))
        cam.zRotation = CGFloat(rig.rotation)
    }

    /// Keeps the ball, flag, reticle and preview dots a constant size on screen.
    private func layoutScreenSpaceNodes() {
        let s = rig.scale
        let up = rig.screenUp

        let ballScale = max(0.15, s * 4.5)
        ball.position = (ballGround + up * (ballHeight * 0.9)).cg
        ball.setScale(CGFloat(ballScale * (1 + min(ballHeight, 40) * 0.012)))
        ballShadow.position = ballGround.cg
        ballShadow.setScale(CGFloat(ballScale * 0.9))
        ballShadow.alpha = CGFloat(0.9 - min(0.6, ballHeight / 50))

        cupNode.setScale(CGFloat(max(Physics.cupRadius, s * 5)))
        flag.setScale(CGFloat(s))
        flag.zRotation = CGFloat(rig.rotation)
        reticle.setScale(CGFloat(s * (isPuttView ? 0.7 : 1.0)))

        for (i, d) in dots.enumerated() {
            if i < previewPoints.count {
                let p = previewPoints[i]
                d.isHidden = false
                d.position = (p.ground + up * (p.h * 0.9)).cg
                d.setScale(CGFloat(s * 2.2))
                d.alpha = previewAlphas[i]
            } else if !d.isHidden {
                d.isHidden = true
            }
        }
    }

    // MARK: - Effects

    private func spawnTrail() {
        let t = SKShapeNode(circleOfRadius: 1)
        t.fillColor = UIColor.white.withAlphaComponent(0.6)
        t.strokeColor = .clear
        t.position = ball.position
        t.setScale(CGFloat(rig.scale * 2.4))
        t.zPosition = 56
        world.addChild(t)
        t.run(SKAction.sequence([
            SKAction.group([SKAction.fadeOut(withDuration: 0.6), SKAction.scale(by: 0.4, duration: 0.6)]),
            SKAction.removeFromParent()
        ]))
    }

    private func burst(at p: Vec2, color: UIColor, count: Int, spread: Double) {
        let s = rig.scale
        for i in 0..<count {
            let n = SKShapeNode(circleOfRadius: 1)
            n.fillColor = color
            n.strokeColor = .clear
            n.position = p.cg
            n.setScale(CGFloat(s * Double.random(in: 1.5...3)))
            n.zPosition = 59
            world.addChild(n)
            let a = Double(i) / Double(count) * 2 * Double.pi + Double.random(in: -0.3...0.3)
            let dist = spread * s * Double.random(in: 0.5...1)
            let move = SKAction.moveBy(x: CGFloat(cos(a) * dist), y: CGFloat(sin(a) * dist), duration: 0.45)
            move.timingMode = .easeOut
            n.run(SKAction.sequence([
                SKAction.group([move, SKAction.fadeOut(withDuration: 0.5)]),
                SKAction.removeFromParent()
            ]))
        }
    }

    private func ripple(at p: Vec2) {
        let s = rig.scale
        for i in 0..<3 {
            let r = SKShapeNode(circleOfRadius: 6)
            r.strokeColor = .white
            r.lineWidth = 1.5
            r.fillColor = .clear
            r.position = p.cg
            r.setScale(CGFloat(s))
            r.alpha = 0
            r.zPosition = 59
            world.addChild(r)
            r.run(SKAction.sequence([
                SKAction.wait(forDuration: Double(i) * 0.18),
                SKAction.fadeAlpha(to: 0.9, duration: 0.05),
                SKAction.group([SKAction.scale(to: CGFloat(s * 5), duration: 0.8), SKAction.fadeOut(withDuration: 0.8)]),
                SKAction.removeFromParent()
            ]))
        }
    }

    private func confetti(at p: Vec2) {
        let colors: [UIColor] = [.systemYellow, .systemPink, .systemTeal, .white, .systemOrange, .systemGreen]
        let s = rig.scale
        for i in 0..<40 {
            let n = SKShapeNode(rectOf: CGSize(width: 2, height: 3.5))
            n.fillColor = colors[i % colors.count]
            n.strokeColor = .clear
            n.position = p.cg
            n.setScale(CGFloat(s))
            n.zPosition = 70
            world.addChild(n)
            let a = Double.random(in: 0...(2 * Double.pi))
            let dist = Double.random(in: 30...110) * s
            let move = SKAction.moveBy(x: CGFloat(cos(a) * dist), y: CGFloat(sin(a) * dist), duration: 1.0)
            move.timingMode = .easeOut
            n.run(SKAction.sequence([
                SKAction.group([move, SKAction.rotate(byAngle: CGFloat.random(in: -8...8), duration: 1.0),
                                SKAction.sequence([SKAction.wait(forDuration: 0.6), SKAction.fadeOut(withDuration: 0.5)])]),
                SKAction.removeFromParent()
            ]))
        }
    }

    // MARK: - Touch: drag anywhere to move the aim target

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        isDragging = true
        if cameraMode == .intro { skipIntro() }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let cur = Vec2(t.location(in: self))
        let prev = Vec2(t.previousLocation(in: self))
        controller?.dragAim(by: cur - prev)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isDragging = false
        controller?.aimDragEnded()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isDragging = false
        controller?.aimDragEnded()
    }
}
