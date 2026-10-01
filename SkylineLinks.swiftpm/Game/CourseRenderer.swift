import SpriteKit
import UIKit

/// Turns hole data into SpriteKit nodes using simple procedural shapes (no art assets needed).
enum CourseRenderer {
    static func build(hole: GolfHole, theme: CourseTheme) -> SKNode {
        let root = SKNode()

        let backdrop = SKShapeNode(rect: hole.bounds.expanded(by: 1200).cg)
        backdrop.fillColor = theme.outOfBounds.ui
        backdrop.strokeColor = .clear
        backdrop.zPosition = 0
        root.addChild(backdrop)

        let field = SKShapeNode(rect: hole.bounds.cg, cornerRadius: 24)
        field.fillColor = theme.heavyRough.ui
        field.strokeColor = .clear
        field.zPosition = 1
        root.addChild(field)

        let stakes = SKShapeNode(path: CGPath(rect: hole.bounds.cg, transform: nil).copy(dashingWithPhase: 0, lengths: [5, 4]))
        stakes.strokeColor = UIColor.white.withAlphaComponent(0.55)
        stakes.lineWidth = 1.2
        stakes.zPosition = 2
        root.addChild(stakes)

        for f in hole.fairways {
            root.addChild(strip(f, width: f.width + 2 * hole.roughWidth, color: theme.rough.ui, z: 3))
        }
        for f in hole.fairways {
            root.addChild(strip(f, width: f.width, color: theme.fairway.ui, z: 4))
            // Lighter centre stripe gives a mown look.
            let stripe = strip(f, width: f.width * 0.45, color: theme.fairway.shaded(1.08).ui.withAlphaComponent(0.6), z: 4.1)
            root.addChild(stripe)
        }

        let tee = shapeNode(hole.teeBox)
        tee.fillColor = theme.fairway.shaded(1.1).ui
        tee.strokeColor = theme.fairway.shaded(0.85).ui
        tee.lineWidth = 0.8
        tee.zPosition = 4.5
        root.addChild(tee)
        for dx in [-3.5, 3.5] {
            let marker = SKShapeNode(circleOfRadius: 0.9)
            marker.position = (hole.tee + Vec2(dx, 2.5)).cg
            marker.fillColor = .white
            marker.strokeColor = .clear
            marker.zPosition = 4.6
            root.addChild(marker)
        }

        for w in hole.water {
            let n = shapeNode(w)
            n.fillColor = theme.water.ui
            n.strokeColor = theme.water.shaded(1.35).ui
            n.lineWidth = 2
            n.zPosition = 5
            root.addChild(n)
            let shine = shapeNode(w.grown(by: -3))
            shine.fillColor = .clear
            shine.strokeColor = UIColor.white.withAlphaComponent(0.18)
            shine.lineWidth = 1
            shine.zPosition = 5.1
            root.addChild(shine)
        }

        for b in hole.bunkers {
            let n = shapeNode(b)
            n.fillColor = theme.sand.ui
            n.strokeColor = theme.sand.shaded(0.8).ui
            n.lineWidth = 1.2
            n.zPosition = 6
            root.addChild(n)
        }

        let fringe = shapeNode(hole.fringe)
        fringe.fillColor = theme.fringe.ui
        fringe.strokeColor = .clear
        fringe.zPosition = 7
        root.addChild(fringe)

        let green = shapeNode(hole.green)
        green.fillColor = theme.green.ui
        green.strokeColor = theme.green.shaded(1.1).ui
        green.lineWidth = 0.5
        green.zPosition = 8
        root.addChild(green)

        root.addChild(slopeArrows(hole: hole, theme: theme))

        for item in hole.decor {
            let n = decorNode(item, theme: theme)
            n.zPosition = 20
            root.addChild(n)
        }
        return root
    }

    static func shapeNode(_ shape: AreaShape) -> SKShapeNode {
        switch shape {
        case let .circle(c, r):
            let n = SKShapeNode(circleOfRadius: CGFloat(max(0.1, r)))
            n.position = c.cg
            return n
        case let .ellipse(c, rx, ry, rot):
            let n = SKShapeNode(ellipseOf: CGSize(width: max(0.2, rx * 2), height: max(0.2, ry * 2)))
            n.position = c.cg
            n.zRotation = CGFloat(rot)
            return n
        case let .rect(c, w, h):
            let n = SKShapeNode(rectOf: CGSize(width: max(0.2, w), height: max(0.2, h)), cornerRadius: CGFloat(min(w, h) * 0.25))
            n.position = c.cg
            return n
        }
    }

    static func strip(_ f: FairwayStrip, width: Double, color: UIColor, z: CGFloat) -> SKShapeNode {
        if f.points.count == 1 {
            let n = SKShapeNode(circleOfRadius: CGFloat(width / 2))
            n.position = f.points[0].cg
            n.fillColor = color
            n.strokeColor = .clear
            n.zPosition = z
            return n
        }
        let path = CGMutablePath()
        path.addLines(between: f.points.map { $0.cg })
        let n = SKShapeNode(path: path)
        n.strokeColor = color
        n.fillColor = .clear
        n.lineWidth = CGFloat(width)
        n.lineCap = .round
        n.lineJoin = .round
        n.zPosition = z
        return n
    }

    static func slopeArrows(hole: GolfHole, theme: CourseTheme) -> SKNode {
        let layer = SKNode()
        layer.zPosition = 9
        let slope = hole.greenSlope
        let mag = slope.length
        guard mag > 0.02 else { return layer }
        let chevron = CGMutablePath()
        chevron.move(to: CGPoint(x: -0.7, y: -0.35))
        chevron.addLine(to: CGPoint(x: 0, y: 0.35))
        chevron.addLine(to: CGPoint(x: 0.7, y: -0.35))
        let c = hole.greenCenter
        let r = hole.green.boundingRadius
        let dir = slope.normalized
        var y = -r
        while y <= r {
            var x = -r
            while x <= r {
                let p = c + Vec2(x, y)
                if hole.green.contains(p) {
                    let n = SKShapeNode(path: chevron)
                    n.strokeColor = UIColor.white
                    n.lineWidth = 0.25
                    n.position = p.cg
                    n.zRotation = CGFloat(slope.angle - Double.pi / 2)
                    n.alpha = 0
                    let peak = CGFloat(min(0.75, 0.25 + mag))
                    let phase = (p - c).dot(dir) / max(1, r)
                    let delay = SKAction.wait(forDuration: max(0, 0.6 + phase * 0.6))
                    let pulse = SKAction.sequence([
                        SKAction.fadeAlpha(to: peak, duration: 0.5),
                        SKAction.fadeAlpha(to: 0.05, duration: 0.9)
                    ])
                    n.run(SKAction.sequence([delay, SKAction.repeatForever(pulse)]))
                    layer.addChild(n)
                }
                x += 3.2
            }
            y += 3.2
        }
        return layer
    }

    static func decorNode(_ item: DecorItem, theme: CourseTheme) -> SKNode {
        let node = SKNode()
        node.position = item.position.cg
        let r = CGFloat(item.radius)
        let base = theme.decor
        let variantShade = 0.9 + Double(item.variant) * 0.08

        let shadow = SKShapeNode(circleOfRadius: r * 1.05)
        shadow.fillColor = UIColor.black.withAlphaComponent(0.22)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: r * 0.35, y: -r * 0.35)
        node.addChild(shadow)

        switch theme.decorStyle {
        case .broadleaf:
            let canopy = SKShapeNode(circleOfRadius: r)
            canopy.fillColor = base.shaded(variantShade).ui
            canopy.strokeColor = base.shaded(0.75).ui
            canopy.lineWidth = 0.6
            node.addChild(canopy)
            let hi = SKShapeNode(circleOfRadius: r * 0.45)
            hi.fillColor = base.shaded(1.3).ui.withAlphaComponent(0.7)
            hi.strokeColor = .clear
            hi.position = CGPoint(x: -r * 0.3, y: r * 0.3)
            node.addChild(hi)
        case .pine, .snowPine:
            let outer = SKShapeNode(circleOfRadius: r)
            outer.fillColor = base.shaded(variantShade).ui
            outer.strokeColor = base.shaded(0.7).ui
            outer.lineWidth = 0.6
            node.addChild(outer)
            let mid = SKShapeNode(circleOfRadius: r * 0.6)
            mid.fillColor = base.shaded(1.15).ui
            mid.strokeColor = .clear
            node.addChild(mid)
            let top = SKShapeNode(circleOfRadius: r * 0.25)
            top.fillColor = theme.decorStyle == .snowPine ? UIColor.white : base.shaded(1.35).ui
            top.strokeColor = .clear
            node.addChild(top)
        case .palm:
            for i in 0..<6 {
                let leaf = SKShapeNode(ellipseOf: CGSize(width: r * 1.1, height: r * 0.35))
                let a = CGFloat(Double(i) * Double.pi / 3 + Double(item.variant) * 0.3)
                leaf.position = CGPoint(x: cos(a) * r * 0.5, y: sin(a) * r * 0.5)
                leaf.zRotation = a
                leaf.fillColor = base.shaded(variantShade).ui
                leaf.strokeColor = base.shaded(0.7).ui
                leaf.lineWidth = 0.4
                node.addChild(leaf)
            }
            let trunk = SKShapeNode(circleOfRadius: r * 0.18)
            trunk.fillColor = UIColor.brown
            trunk.strokeColor = .clear
            node.addChild(trunk)
        case .cactus:
            let body = SKShapeNode(circleOfRadius: r)
            body.fillColor = base.shaded(variantShade).ui
            body.strokeColor = base.shaded(1.4).ui
            body.lineWidth = 0.4
            node.addChild(body)
            let arm = SKShapeNode(circleOfRadius: r * 0.5)
            arm.fillColor = base.shaded(1.1).ui
            arm.strokeColor = .clear
            arm.position = CGPoint(x: r * 0.8, y: r * 0.3)
            node.addChild(arm)
        case .rock:
            let rock = SKShapeNode(ellipseOf: CGSize(width: r * 2, height: r * 1.5))
            rock.fillColor = base.shaded(variantShade).ui
            rock.strokeColor = base.shaded(0.7).ui
            rock.lineWidth = 0.5
            rock.zRotation = CGFloat(item.variant) * 0.7
            node.addChild(rock)
            let hi = SKShapeNode(ellipseOf: CGSize(width: r * 0.9, height: r * 0.5))
            hi.fillColor = base.shaded(1.3).ui
            hi.strokeColor = .clear
            hi.position = CGPoint(x: -r * 0.3, y: r * 0.25)
            node.addChild(hi)
        }
        return node
    }
}
