import SceneKit
import UIKit
import simd

/// Procedural 3D club models (no asset files). Each club has its grip end at the node origin
/// and the head at (0, -length, 0). Local +X is the clubface direction, +Z points toward the toe.
enum ClubModel3D {
    /// Club length in yards (slightly stylised).
    static func length(for type: ClubType) -> Double {
        switch type {
        case .driver: return 1.25
        case .wood3: return 1.2
        case .wood5: return 1.16
        case .iron3: return 1.1
        case .iron5: return 1.07
        case .iron7: return 1.04
        case .iron9: return 1.01
        case .pitchingWedge: return 1.0
        case .sandWedge: return 0.98
        case .lobWedge: return 0.97
        case .putter: return 0.95
        }
    }

    private static func shiny(_ color: UIColor, shininess: CGFloat = 60) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.specular.contents = UIColor.white
        m.shininess = shininess
        m.lightingModel = .blinn
        return m
    }

    static func make(type: ClubType, accent: UIColor) -> (node: SCNNode, head: SCNNode) {
        let root = SCNNode()
        let L = length(for: type)

        // Shaft in the card's rarity colour, plus a dark rubber grip.
        let shaft = SCNCylinder(radius: 0.011, height: CGFloat(L))
        shaft.radialSegmentCount = 10
        shaft.materials = [shiny(accent)]
        let shaftNode = SCNNode(geometry: shaft)
        shaftNode.position = SCNVector3(x: 0, y: Float(-L / 2), z: 0)
        root.addChildNode(shaftNode)

        let grip = SCNCylinder(radius: 0.02, height: 0.28)
        grip.radialSegmentCount = 10
        let gripMat = SCNMaterial()
        gripMat.diffuse.contents = UIColor(white: 0.12, alpha: 1)
        gripMat.lightingModel = .lambert
        grip.materials = [gripMat]
        let gripNode = SCNNode(geometry: grip)
        gripNode.position = SCNVector3(x: 0, y: -0.14, z: 0)
        root.addChildNode(gripNode)

        let chrome = shiny(UIColor(white: 0.78, alpha: 1), shininess: 90)
        let head: SCNNode
        switch type {
        case .driver, .wood3, .wood5:
            let size: Double = type == .driver ? 0.07 : (type == .wood3 ? 0.06 : 0.055)
            let sphere = SCNSphere(radius: CGFloat(size))
            sphere.segmentCount = 18
            sphere.materials = [shiny(UIColor(white: 0.1, alpha: 1), shininess: 80)]
            head = SCNNode(geometry: sphere)
            head.scale = SCNVector3(x: 0.9, y: 0.55, z: 1.45)
            head.position = SCNVector3(x: 0, y: Float(-L + size * 0.5), z: Float(size * 1.0))
            // A thin accent stripe on the crown.
            let stripe = SCNBox(width: 0.008, height: 0.004, length: CGFloat(size * 1.6), chamferRadius: 0)
            stripe.materials = [shiny(accent)]
            let stripeNode = SCNNode(geometry: stripe)
            stripeNode.position = SCNVector3(x: Float(-size * 0.2), y: Float(size * 0.98), z: 0)
            head.addChildNode(stripeNode)
        case .putter:
            let box = SCNBox(width: 0.035, height: 0.03, length: 0.11, chamferRadius: 0.008)
            box.materials = [chrome]
            head = SCNNode(geometry: box)
            head.position = SCNVector3(x: 0, y: Float(-L + 0.015), z: 0.05)
        default:
            let isWedge = type == .pitchingWedge || type == .sandWedge || type == .lobWedge
            let box = SCNBox(width: 0.018, height: isWedge ? 0.065 : 0.055, length: 0.085, chamferRadius: 0.005)
            box.materials = [chrome]
            head = SCNNode(geometry: box)
            head.position = SCNVector3(x: 0, y: Float(-L + 0.025), z: 0.04)
        }
        root.addChildNode(head)
        return (root, head)
    }
}

/// Places a club at the ball and animates backswing (from the power meter), the downswing,
/// impact and follow-through, leaving a coloured trail along the club head's path.
final class ClubSwingRig {
    /// Positioned at the hands and oriented to the swing plane.
    let root = SCNNode()
    /// Rotated about local Y after impact to show an in-to-out / out-to-in path.
    private let pathTilt = SCNNode()
    /// Rotated about local Z for the swing itself.
    private let arm = SCNNode()
    private var head: SCNNode?
    private var modelKey = ""
    private var clubType: ClubType = .driver

    enum State {
        case hidden
        case address
        case downswing
        case finished
    }

    private(set) var state: State = .hidden
    private var angle = 0.0
    private var startAngle = 0.0
    private var endAngle = 2.5
    private var tilt = 0.0
    private var targetTilt = 0.0
    private var downTime = 0.0
    private var impactTime = 0.2
    private var followTime = 0.4
    private var impactPending = false
    private var impactFired = false
    private var finishHold = 0.0
    private var trailGeometry: SCNGeometry?

    init() {
        root.addChildNode(pathTilt)
        pathTilt.addChildNode(arm)
        root.isHidden = true
    }

    var isAtAddress: Bool { state == .address }

    /// Builds the club model when the selected club (or card) changes.
    @discardableResult
    func setClub(type: ClubType, key: String, accent: UIColor) -> Bool {
        guard key != modelKey else { return false }
        modelKey = key
        clubType = type
        for child in arm.childNodes { child.removeFromParentNode() }
        let model = ClubModel3D.make(type: type, accent: accent)
        arm.addChildNode(model.node)
        head = model.head
        return true
    }

    /// Puts the club at address behind the ball, aimed down `aimDir`.
    func place(ballGround: Vec2, groundHeight: Double, aimDir: Vec2) {
        guard state != .downswing else { return }
        if state != .address {
            angle = 0
            tilt = 0
        }
        let f = aimDir.length > 0.01 ? aimDir.normalized : Vec2(0, 1)
        let left = f.leftPerp
        let L = ClubModel3D.length(for: clubType)
        let x = SIMD3<Float>(Float(f.x), 0, Float(-f.y))
        let leftS = SIMD3<Float>(Float(left.x), 0, Float(-left.y))
        let up = SIMD3<Float>(0, 1, 0)
        let toHands = clubType == .putter ? simd_normalize(leftS * 0.3 + up * 0.95) : simd_normalize(leftS * 0.55 + up * 0.835)
        let headPos = SIMD3<Float>(Float(ballGround.x - f.x * 0.07), Float(groundHeight + 0.01), Float(-(ballGround.y - f.y * 0.07)))
        let hands = headPos + toHands * Float(L)
        let z = simd_cross(x, toHands)
        root.simdTransform = simd_float4x4(SIMD4<Float>(x, 0), SIMD4<Float>(toHands, 0), SIMD4<Float>(z, 0), SIMD4<Float>(hands, 1))
        state = .address
        root.isHidden = false
        root.opacity = 1
        apply()
    }

    func hide() {
        state = .hidden
        root.isHidden = true
        impactPending = false
    }

    /// Starts the downswing. Returns false if the club is not at address (then launch immediately).
    func startDownswing(sideSpin: Double, outcomeColor: UIColor) -> Bool {
        guard state == .address else { return false }
        state = .downswing
        startAngle = min(angle, -0.15)
        downTime = 0
        impactPending = false
        impactFired = false
        targetTilt = (sideSpin * 0.15).clamped(-0.35, 0.35)
        if clubType == .putter {
            impactTime = 0.28
            followTime = 0.3
            endAngle = -startAngle * 0.9
        } else {
            impactTime = 0.2
            followTime = 0.42
            endAngle = 2.5
        }
        let geo = SCNSphere(radius: 0.035)
        geo.segmentCount = 6
        let m = SCNMaterial()
        m.diffuse.contents = outcomeColor.withAlphaComponent(0.85)
        m.lightingModel = .constant
        geo.materials = [m]
        trailGeometry = geo
        return true
    }

    /// True once, at the moment the club reaches the ball.
    func takeImpact() -> Bool {
        if impactPending {
            impactPending = false
            return true
        }
        return false
    }

    /// Backswing angle for a given meter power.
    private func backswing(_ power: Double) -> Double {
        let p = min(max(power, 0), SwingMeterState.maxPower)
        return clubType == .putter ? -(0.1 + 0.55 * p) : -(0.2 + 2.2 * p)
    }

    func update(_ dt: Double, meter: SwingMeterState?, trailParent: SCNNode) {
        switch state {
        case .hidden:
            return
        case .address:
            var target = 0.0
            if let m = meter {
                switch m.phase {
                case .charging: target = backswing(m.power)
                case .accuracy, .finished: target = backswing(m.lockedPower)
                case .idle: target = 0
                }
            }
            angle += (target - angle) * (1 - exp(-14 * dt))
        case .downswing:
            downTime += dt
            if downTime < impactTime {
                let u = downTime / impactTime
                angle = startAngle * (1 - u * u)
            } else {
                if !impactFired {
                    impactFired = true
                    impactPending = true
                }
                let u = min(1, (downTime - impactTime) / followTime)
                angle = endAngle * (1 - (1 - u) * (1 - u))
                tilt = targetTilt * u
                if u >= 1 {
                    state = .finished
                    finishHold = 0
                }
            }
            spawnTrail(in: trailParent)
        case .finished:
            finishHold += dt
            root.opacity = CGFloat(max(0, 1 - max(0, finishHold - 0.6) / 0.4))
            if finishHold > 1.0 {
                hide()
            }
        }
        apply()
    }

    private func apply() {
        arm.eulerAngles = SCNVector3(x: 0, y: 0, z: Float(angle))
        pathTilt.eulerAngles = SCNVector3(x: 0, y: Float(tilt), z: 0)
    }

    private func spawnTrail(in parent: SCNNode) {
        guard let head = head, let geo = trailGeometry else { return }
        let n = SCNNode(geometry: geo)
        n.position = head.worldPosition
        parent.addChildNode(n)
        n.runAction(SCNAction.sequence([
            SCNAction.fadeOut(duration: 0.9),
            SCNAction.removeFromParentNode()
        ]))
    }
}
