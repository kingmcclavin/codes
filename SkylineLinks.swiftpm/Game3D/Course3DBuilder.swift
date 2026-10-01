import SceneKit
import UIKit

/// Builds the 3D course: a terrain mesh that follows the hole's elevation, textured with a
/// top-down painting of the hole (so fairway/green/bunker edges stay crisp), plus 3D scenery.
/// SceneKit axes: X = world x, Y = height, Z = -world y (so "down the hole" is -Z).
enum Course3DBuilder {
    static func build(hole: GolfHole, theme: CourseTheme) -> SCNNode {
        let root = SCNNode()
        let rect = hole.bounds.expanded(by: 90)
        let ppy = min(4.0, 4096.0 / max(rect.width, rect.height))
        let image = CourseTexture.makeImage(hole: hole, theme: theme, rect: rect, pixelsPerYard: ppy)

        let terrain = SCNNode(geometry: terrainGeometry(hole: hole, rect: rect))
        let mat = SCNMaterial()
        mat.diffuse.contents = image
        mat.diffuse.mipFilter = .linear
        mat.diffuse.wrapS = .clamp
        mat.diffuse.wrapT = .clamp
        mat.lightingModel = .lambert
        mat.isDoubleSided = true
        terrain.geometry?.materials = [mat]
        root.addChildNode(terrain)

        // Endless ground beyond the painted area.
        let plane = SCNPlane(width: 5000, height: 5000)
        let planeMat = SCNMaterial()
        planeMat.diffuse.contents = theme.outOfBounds.ui
        planeMat.lightingModel = .lambert
        plane.materials = [planeMat]
        let planeNode = SCNNode(geometry: plane)
        planeNode.eulerAngles = SCNVector3(x: -Float.pi / 2, y: 0, z: 0)
        planeNode.position = SCNVector3(x: Float(rect.center.x), y: Float(min(0, hole.greenElevation) - 0.6), z: Float(-rect.center.y))
        root.addChildNode(planeNode)

        let palette = DecorPalette(theme: theme)
        for item in hole.decor {
            let node = decorNode(item, style: theme.decorStyle, palette: palette)
            let g = hole.groundHeight(at: item.position)
            node.position = SCNVector3(x: Float(item.position.x), y: Float(g), z: Float(-item.position.y))
            node.eulerAngles = SCNVector3(x: 0, y: Float(item.variant) * 1.3, z: 0)
            root.addChildNode(node)
        }
        return root
    }

    // MARK: Terrain mesh

    private static func terrainGeometry(hole: GolfHole, rect: WorldRect) -> SCNGeometry {
        let step = max(3.0, max(rect.width, rect.height) / 220)
        let nx = max(2, Int((rect.width / step).rounded(.up)) + 1)
        let nz = max(2, Int((rect.height / step).rounded(.up)) + 1)
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        vertices.reserveCapacity(nx * nz)
        normals.reserveCapacity(nx * nz)
        uvs.reserveCapacity(nx * nz)

        for j in 0..<nz {
            let y = rect.minY + Double(j) * rect.height / Double(nz - 1)
            for i in 0..<nx {
                let x = rect.minX + Double(i) * rect.width / Double(nx - 1)
                let h = hole.groundHeight(at: Vec2(x, y))
                vertices.append(SCNVector3(x: Float(x), y: Float(h), z: Float(-y)))
                let dhdx = (hole.groundHeight(at: Vec2(x + 1, y)) - hole.groundHeight(at: Vec2(x - 1, y))) / 2
                let dhdy = (hole.groundHeight(at: Vec2(x, y + 1)) - hole.groundHeight(at: Vec2(x, y - 1))) / 2
                let n = normalized(-dhdx, 1, dhdy)
                normals.append(n)
                uvs.append(CGPoint(x: (x - rect.minX) / rect.width, y: (rect.maxY - y) / rect.height))
            }
        }

        var indices: [UInt32] = []
        indices.reserveCapacity((nx - 1) * (nz - 1) * 6)
        for j in 0..<(nz - 1) {
            for i in 0..<(nx - 1) {
                let a = UInt32(j * nx + i)
                let b = a + 1
                let c = a + UInt32(nx)
                let d = c + 1
                indices.append(contentsOf: [a, b, d, a, d, c])
            }
        }

        let sources = [
            SCNGeometrySource(vertices: vertices),
            SCNGeometrySource(normals: normals),
            SCNGeometrySource(textureCoordinates: uvs)
        ]
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: sources, elements: [element])
    }

    private static func normalized(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 {
        let l = max(1e-6, (x * x + y * y + z * z).squareRoot())
        return SCNVector3(x: Float(x / l), y: Float(y / l), z: Float(z / l))
    }

    // MARK: Scenery

    struct DecorPalette {
        let leaf: SCNMaterial
        let leafLight: SCNMaterial
        let trunk: SCNMaterial
        let snow: SCNMaterial

        init(theme: CourseTheme) {
            leaf = Course3DBuilder.material(theme.decor.ui)
            leafLight = Course3DBuilder.material(theme.decor.shaded(1.25).ui)
            trunk = Course3DBuilder.material(UIColor(red: 0.42, green: 0.29, blue: 0.18, alpha: 1))
            snow = Course3DBuilder.material(UIColor(white: 0.96, alpha: 1))
        }
    }

    static func material(_ color: UIColor, lit: Bool = true) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = lit ? .lambert : .constant
        return m
    }

    private static func part(_ geometry: SCNGeometry, _ material: SCNMaterial, y: Double, x: Double = 0) -> SCNNode {
        geometry.materials = [material]
        let n = SCNNode(geometry: geometry)
        n.position = SCNVector3(x: Float(x), y: Float(y), z: 0)
        return n
    }

    static func decorNode(_ item: DecorItem, style: DecorStyle, palette: DecorPalette) -> SCNNode {
        let node = SCNNode()
        let r = item.radius
        let h = item.height
        let leaf = item.variant == 1 ? palette.leafLight : palette.leaf
        switch style {
        case .broadleaf:
            node.addChildNode(part(SCNCylinder(radius: 0.35, height: CGFloat(h * 0.5)), palette.trunk, y: h * 0.25))
            let canopy = SCNSphere(radius: CGFloat(r))
            canopy.segmentCount = 12
            node.addChildNode(part(canopy, leaf, y: max(h * 0.5, h - r)))
        case .pine, .snowPine:
            node.addChildNode(part(SCNCylinder(radius: 0.3, height: CGFloat(h * 0.3)), palette.trunk, y: h * 0.15))
            node.addChildNode(part(SCNCone(topRadius: 0, bottomRadius: CGFloat(r), height: CGFloat(h * 0.85)), leaf, y: h * 0.15 + h * 0.425))
            if style == .snowPine {
                node.addChildNode(part(SCNCone(topRadius: 0, bottomRadius: CGFloat(r * 0.45), height: CGFloat(h * 0.3)), palette.snow, y: h * 0.85))
            }
        case .palm:
            node.addChildNode(part(SCNCylinder(radius: 0.3, height: CGFloat(h * 0.9)), palette.trunk, y: h * 0.45))
            let fronds = part(SCNSphere(radius: CGFloat(r)), leaf, y: h * 0.9)
            fronds.scale = SCNVector3(x: 1, y: 0.22, z: 1)
            node.addChildNode(fronds)
        case .cactus:
            node.addChildNode(part(SCNCapsule(capRadius: CGFloat(r * 0.45), height: CGFloat(h)), leaf, y: h / 2))
            node.addChildNode(part(SCNCapsule(capRadius: CGFloat(r * 0.3), height: CGFloat(h * 0.45)), leaf, y: h * 0.55, x: r * 0.75))
        case .rock:
            let rock = part(SCNSphere(radius: CGFloat(r)), leaf, y: r * 0.15)
            rock.scale = SCNVector3(x: 1, y: 0.55, z: 0.85)
            node.addChildNode(rock)
        }
        return node
    }
}

/// Paints the hole from above into an image used as the terrain texture.
enum CourseTexture {
    static func makeImage(hole: GolfHole, theme: CourseTheme, rect: WorldRect, pixelsPerYard ppy: Double) -> UIImage {
        let size = CGSize(width: max(16, rect.width * ppy), height: max(16, rect.height * ppy))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        // World (yards, y up) -> image pixels (y down).
        let toImage = CGAffineTransform(a: CGFloat(ppy), b: 0, c: 0, d: CGFloat(-ppy),
                                        tx: CGFloat(-rect.minX * ppy), ty: CGFloat(rect.maxY * ppy))
        return renderer.image { ctx in
            let c = ctx.cgContext
            c.setFillColor(theme.outOfBounds.ui.cgColor)
            c.fill(CGRect(origin: .zero, size: size))
            c.concatenate(toImage)
            draw(hole: hole, theme: theme, in: c)
        }
    }

    private static func path(for shape: AreaShape) -> CGPath {
        let p = CGMutablePath()
        switch shape {
        case let .circle(center, r):
            p.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        case let .ellipse(center, rx, ry, rot):
            let t = CGAffineTransform(translationX: CGFloat(center.x), y: CGFloat(center.y)).rotated(by: CGFloat(rot))
            p.addEllipse(in: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry), transform: t)
        case let .rect(center, w, h):
            let r = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
            let corner = CGFloat(min(w, h) * 0.25)
            p.addRoundedRect(in: r, cornerWidth: corner, cornerHeight: corner)
        }
        return p
    }

    private static func fill(_ shape: AreaShape, _ color: UIColor, _ c: CGContext) {
        c.setFillColor(color.cgColor)
        c.addPath(path(for: shape))
        c.fillPath()
    }

    private static func stripPath(_ f: FairwayStrip, width: Double) -> CGPath {
        let p = CGMutablePath()
        if f.points.count == 1 {
            let q = f.points[0]
            let r = width / 2
            p.addEllipse(in: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r))
            return p
        }
        let line = CGMutablePath()
        line.addLines(between: f.points.map { $0.cg })
        return line.copy(strokingWithWidth: CGFloat(width), lineCap: .round, lineJoin: .round, miterLimit: 10)
    }

    private static func draw(hole: GolfHole, theme: CourseTheme, in c: CGContext) {
        // Heavy rough inside the course boundary.
        c.setFillColor(theme.heavyRough.ui.cgColor)
        c.addPath(CGPath(roundedRect: hole.bounds.cg, cornerWidth: 20, cornerHeight: 20, transform: nil))
        c.fillPath()

        // Tree shadows baked into the ground.
        c.setFillColor(UIColor.black.withAlphaComponent(0.22).cgColor)
        for item in hole.decor {
            let r = item.radius * 1.1
            let p = item.position + Vec2(item.radius * 0.6, -item.radius * 0.6)
            c.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        }
        c.fillPath()

        // Rough, then fairway with mown stripes.
        c.setFillColor(theme.rough.ui.cgColor)
        for f in hole.fairways {
            c.addPath(stripPath(f, width: f.width + 2 * hole.roughWidth))
        }
        c.fillPath()

        let fairwayPath = CGMutablePath()
        for f in hole.fairways {
            fairwayPath.addPath(stripPath(f, width: f.width))
        }
        c.setFillColor(theme.fairway.ui.cgColor)
        c.addPath(fairwayPath)
        c.fillPath()
        c.saveGState()
        c.addPath(fairwayPath)
        c.clip()
        c.setFillColor(theme.fairway.shaded(1.1).ui.cgColor)
        var y = hole.bounds.minY
        while y < hole.bounds.maxY {
            c.fill(CGRect(x: hole.bounds.minX, y: y, width: hole.bounds.width, height: 7))
            y += 14
        }
        c.restoreGState()

        // Tee box.
        fill(hole.teeBox, theme.fairway.shaded(1.12).ui, c)
        c.setFillColor(UIColor.white.cgColor)
        for dx in [-3.5, 3.5] {
            let p = hole.tee + Vec2(dx, 2.5)
            c.fillEllipse(in: CGRect(x: p.x - 0.5, y: p.y - 0.5, width: 1, height: 1))
        }

        // Water with a light shoreline.
        for w in hole.water {
            c.setStrokeColor(theme.water.shaded(1.4).ui.cgColor)
            c.setLineWidth(1.6)
            c.addPath(path(for: w))
            c.strokePath()
            fill(w, theme.water.ui, c)
            c.setStrokeColor(UIColor.white.withAlphaComponent(0.2).cgColor)
            c.setLineWidth(0.4)
            c.addPath(path(for: w.grown(by: -2.5)))
            c.strokePath()
        }

        // Bunkers with a darker lip.
        for b in hole.bunkers {
            c.setStrokeColor(theme.sand.shaded(0.75).ui.cgColor)
            c.setLineWidth(0.9)
            c.addPath(path(for: b))
            c.strokePath()
            fill(b, theme.sand.ui, c)
        }

        // Fringe and green with fine stripes and slope chevrons.
        fill(hole.fringe, theme.fringe.ui, c)
        fill(hole.green, theme.green.ui, c)
        c.saveGState()
        c.addPath(path(for: hole.green))
        c.clip()
        c.setFillColor(theme.green.shaded(1.07).ui.cgColor)
        let gc = hole.greenCenter
        let gr = hole.green.boundingRadius
        var x = gc.x - gr
        while x < gc.x + gr {
            c.fill(CGRect(x: x, y: gc.y - gr, width: 1.5, height: gr * 2))
            x += 3
        }
        let slope = hole.greenSlope
        if slope.length > 0.02 {
            let dir = slope.normalized
            let side = dir.leftPerp
            c.setStrokeColor(UIColor.white.withAlphaComponent(CGFloat(min(0.55, 0.2 + slope.length * 0.6))).cgColor)
            c.setLineWidth(0.22)
            c.setLineCap(.round)
            var yy = gc.y - gr
            while yy <= gc.y + gr {
                var xx = gc.x - gr
                while xx <= gc.x + gr {
                    let p = Vec2(xx, yy)
                    if hole.green.contains(p) {
                        let tip = p + dir * 0.45
                        c.move(to: (p - dir * 0.3 + side * 0.6).cg)
                        c.addLine(to: tip.cg)
                        c.addLine(to: (p - dir * 0.3 - side * 0.6).cg)
                    }
                    xx += 3.2
                }
                yy += 3.2
            }
            c.strokePath()
        }
        c.restoreGState()

        // Out-of-bounds stakes.
        c.setStrokeColor(UIColor.white.withAlphaComponent(0.6).cgColor)
        c.setLineWidth(0.5)
        c.setLineDash(phase: 0, lengths: [3, 2])
        c.addPath(CGPath(rect: hole.bounds.cg, transform: nil))
        c.strokePath()
        c.setLineDash(phase: 0, lengths: [])
    }
}
