import Foundation

/// What a hole should be, before geometry is generated.
struct HoleBlueprint {
    var par: Int
    var archetype: HoleArchetype
    var calm: Bool = false
    var lengthBias: Double = 0
}

/// Builds hole geometry from reusable components (fairway strips, bunkers, water, elevation).
/// Generation is deterministic: the same seed always produces the same hole.
enum CourseGenerator {
    private static let par3Friendly: [HoleArchetype] = [.straight, .waterCrossing, .islandGreen, .bunkerComplex, .elevatedGreen, .mountain, .coastal]

    static func makeHole(number: Int, blueprint bp: HoleBlueprint, theme: CourseTheme, difficulty: Int, botStrokes: Int, seed: UInt64) -> GolfHole {
        var rng = SeededRandom(seed: seed)
        let d = Double(difficulty)
        let par = bp.par
        var archetype = bp.archetype
        if par == 3 && !par3Friendly.contains(archetype) { archetype = .straight }
        if par != 3 && archetype == .islandGreen { archetype = .waterCrossing }

        var length: Double
        switch par {
        case 3: length = 132 + d * 6 + rng.range(-12, 22)
        case 5: length = 470 + d * 7 + rng.range(-10, 30)
        default: length = 330 + d * 9 + rng.range(-20, 30)
        }
        length += bp.lengthBias
        if archetype == .mountain { length += par == 3 ? 20 : 35 }

        let fw = max(20, 44 - d * 1.9 + rng.range(-3, 3)) * (archetype == .narrow ? 0.68 : 1)
        let roughW = archetype == .narrow ? 6.0 : 9 + rng.range(0, 4)
        let grx = max(8.5, 13.5 - d * 0.35 + rng.range(-1, 1.5))
        let gry = grx * rng.range(1.0, 1.3)
        let grot = rng.range(-0.5, 0.5)
        let gReach = max(grx, gry)

        var elevation = 0.0
        var ramp = 0.75
        var fairways: [FairwayStrip] = []
        var bunkers: [AreaShape] = []
        var water: [AreaShape] = []
        var trees: [DecorItem] = []
        var g = Vec2(rng.range(-8, 8), length)
        let fwStart = 34.0
        var sideMargin = 42.0
        let tee = Vec2.zero

        switch archetype {
        case .straight, .bunkerComplex, .narrow, .elevatedGreen, .mountain:
            if par > 3 {
                let midX = rng.range(-14, 14)
                fairways = [FairwayStrip(points: [Vec2(0, fwStart), Vec2(midX, length * 0.55), Vec2(g.x, g.y - gry - 3)], width: fw)]
            }
            if archetype == .narrow { sideMargin = 24 }
            if archetype == .elevatedGreen {
                elevation = par == 3 ? rng.range(8, 18) : rng.range(10, 22)
                ramp = 0.8
            }
            if archetype == .mountain {
                elevation = -(par == 3 ? rng.range(15, 28) : rng.range(24, 42))
                ramp = 0.1
            }

        case .doglegLeft, .doglegRight:
            let s: Double = archetype == .doglegLeft ? -1 : 1
            let corner = par == 5 ? rng.range(265, 290) : rng.range(232, 252)
            let turn = degreesToRadians(rng.range(32, 50))
            let after = max(80, length - corner)
            let outDir = Vec2(angle: Double.pi / 2 - s * turn)
            let cornerPt = Vec2(0, corner)
            g = cornerPt + outDir * after
            let strip = FairwayStrip(points: [Vec2(0, fwStart), Vec2(0, corner - 10), cornerPt + outDir * 18, g - outDir * (gReach + 3)], width: fw)
            fairways = [strip]
            bunkers.append(.ellipse(center: Vec2(s * (fw / 2 + 6), corner - 14), rx: 6, ry: 12, rotation: 0))
            bunkers.append(.ellipse(center: Vec2(-s * (fw / 2 + 2), corner + 6), rx: 5, ry: 10, rotation: 0))
            // Trees guard the corner so cutting it needs a high shot.
            var f = 0.38
            while f < 0.8 {
                let p = g * f + Vec2(rng.range(-6, 6), rng.range(-6, 6))
                if strip.distance(to: p) > fw / 2 + roughW + 5 {
                    trees.append(DecorItem(position: p, radius: rng.range(5, 7), height: rng.range(14, 19), blocking: true, variant: rng.int(0, 2)))
                }
                f += 0.06
            }

        case .waterCrossing:
            if par == 3 {
                water.append(.rect(center: Vec2(g.x, g.y - gry - 13), width: gReach * 2 + 44, height: 16))
            } else {
                let waterY = par == 4 ? rng.range(165, 185) : rng.range(295, 318)
                water.append(.rect(center: Vec2(0, waterY), width: 2 * (fw / 2 + roughW) + 90, height: 20))
                fairways = [
                    FairwayStrip(points: [Vec2(0, fwStart), Vec2(0, waterY - 17)], width: fw),
                    FairwayStrip(points: [Vec2(0, waterY + 17), Vec2(rng.range(-12, 12), (waterY + length) / 2), Vec2(g.x, g.y - gry - 3)], width: fw)
                ]
            }

        case .islandGreen:
            let waterR = gReach + rng.range(13, 18)
            water.append(.circle(center: g, radius: waterR))
            fairways = [FairwayStrip(points: [g], width: (gReach + 9) * 2)]

        case .splitFairway:
            let w2 = fw * 0.72
            let midY = length * 0.62
            let end = Vec2(g.x, g.y - gry - 3)
            fairways = [
                FairwayStrip(points: [Vec2(0, fwStart), Vec2(-30, 140), Vec2(-34, midY), end], width: w2),
                FairwayStrip(points: [Vec2(0, fwStart), Vec2(30, 140), Vec2(36, midY), end], width: w2)
            ]
            let hazard = AreaShape.ellipse(center: Vec2(0, (150 + midY) / 2), rx: 11, ry: max(20, (midY - 150) / 2 * 0.8), rotation: 0)
            if difficulty >= 4 { water.append(hazard) } else { bunkers.append(hazard) }

        case .coastal:
            let s = rng.sign()
            g = Vec2(s * rng.range(4, 12), length)
            let edge: Double
            if par > 3 {
                fairways = [FairwayStrip(points: [Vec2(0, fwStart), Vec2(s * 8, length * 0.55), Vec2(g.x, g.y - gry - 3)], width: fw)]
                edge = s * (fw / 2 + roughW + 22)
            } else {
                edge = g.x + s * (gReach + 22)
            }
            water.append(.rect(center: Vec2(edge + s * 260, length / 2), width: 520, height: length + 420))
        }

        // Approach direction (from the green back toward the player).
        let approachFrom: Vec2 = fairways.first(where: { $0.points.count > 1 })?.points.last ?? tee
        let approach = (approachFrom - g).angle

        // Par 3s get a short collar of fairway in front of the green.
        if par == 3 && fairways.isEmpty {
            let a = Vec2(angle: approach)
            fairways = [FairwayStrip(points: [g + a * (gReach + 34), g + a * (gReach + 2)], width: fw * 0.8)]
        }

        // Fairway bunkers in the driving zone.
        if par > 3 && archetype != .splitFairway {
            let count = archetype == .bunkerComplex ? 3 : (rng.chance(0.3 + d * 0.05) ? 1 : 0)
            if let main = fairways.first(where: { $0.points.count > 1 }) {
                for i in 0..<count {
                    let y = [228.0, 252.0, 276.0][i % 3] + rng.range(-6, 6)
                    if let x = pathX(main, atY: y) {
                        let side: Double = (i % 2 == 0) ? rng.sign() : -1
                        let inset = archetype == .bunkerComplex ? 2.0 : 5.0
                        bunkers.append(.ellipse(center: Vec2(x + side * (main.width / 2 + inset), y), rx: rng.range(5, 7), ry: rng.range(9, 13), rotation: rng.range(-0.3, 0.3)))
                    }
                }
            }
        }

        // Greenside bunkers.
        var greenside: [Double] = []
        switch archetype {
        case .bunkerComplex: greenside = [approach + 0.85, approach - 0.85, approach + 2.0, approach + Double.pi]
        case .elevatedGreen: greenside = [approach + 0.75, approach - 0.75, approach + Double.pi]
        case .islandGreen: greenside = []
        default:
            let n = 1 + rng.int(0, min(2, difficulty / 3 + 1))
            greenside = Array([approach + 0.9, approach - 1.1, approach + Double.pi + 0.3].prefix(n))
        }
        for a in greenside {
            let dir = Vec2(angle: a)
            let c = g + dir * (gReach + rng.range(4.5, 7))
            bunkers.append(.ellipse(center: c, rx: rng.range(3.5, 5.5), ry: rng.range(6, 9), rotation: a))
        }

        let green = AreaShape.ellipse(center: g, rx: grx, ry: gry, rotation: grot)
        let cup = g + Vec2(rng.range(-0.5, 0.5) * grx, rng.range(-0.5, 0.5) * gry).rotated(by: grot)

        // Green slope and wind.
        let slopeMag = 0.1 + d * 0.045 + rng.range(0, 0.12)
        let slope = Vec2(angle: rng.range(0, 2 * Double.pi)) * slopeMag
        var wind = Wind(direction: rng.range(0, 2 * Double.pi), speedMPH: rng.range(0, 3 + d * 1.5 + theme.windBonus).rounded())
        if bp.calm { wind = .calm }

        // Bounds.
        var xs: [Double] = [tee.x - 10, tee.x + 10, g.x - gReach, g.x + gReach]
        var ys: [Double] = [tee.y - 10, g.y + gReach]
        for f in fairways {
            for p in f.points {
                xs.append(p.x - f.width / 2 - roughW)
                xs.append(p.x + f.width / 2 + roughW)
                ys.append(p.y + f.width / 2)
            }
        }
        let bounds = WorldRect(minX: (xs.min() ?? -50) - sideMargin, minY: -28,
                               maxX: (xs.max() ?? 50) + sideMargin, maxY: (ys.max() ?? length) + 36)

        // Scenery.
        var decor = trees
        let target = 46 + rng.int(0, 20)
        let area = bounds.expanded(by: 70)
        var attempts = 0
        while decor.count < target && attempts < 700 {
            attempts += 1
            let p = Vec2(rng.range(area.minX, area.maxX), rng.range(area.minY, area.maxY))
            if p.distance(to: tee) < 24 { continue }
            if p.distance(to: g) < gReach + 16 { continue }
            if water.contains(where: { $0.grown(by: 4).contains(p) }) { continue }
            if bunkers.contains(where: { $0.grown(by: 3).contains(p) }) { continue }
            if fairways.contains(where: { $0.distance(to: p) < $0.width / 2 + roughW + 6 }) { continue }
            if segmentDistance(p, tee, approachFrom) < 16 && par == 3 { continue }
            if segmentDistance(p, approachFrom, g) < gReach + 10 { continue }
            let inside = bounds.contains(p)
            let height: Double
            let radius: Double
            switch theme.decorStyle {
            case .rock: radius = rng.range(2, 4.5); height = 3
            case .cactus: radius = rng.range(1.5, 3); height = 6
            default: radius = rng.range(3, 6.5); height = rng.range(10, 17)
            }
            decor.append(DecorItem(position: p, radius: radius, height: height, blocking: inside, variant: rng.int(0, 2)))
        }

        let names = holeNames[archetype] ?? ["The Hole"]
        let name = names[(number + Int(seed % 7)) % names.count]

        return GolfHole(
            number: number,
            name: name,
            par: par,
            archetype: archetype,
            tee: tee,
            cup: cup,
            green: green,
            fringe: green.grown(by: 2.5),
            fairways: fairways,
            roughWidth: roughW,
            bunkers: bunkers,
            water: water,
            teeBox: .rect(center: tee, width: 12, height: 9),
            bounds: bounds,
            greenElevation: elevation,
            elevationRampStart: ramp,
            greenSlope: slope,
            greenSpeed: theme.greenSpeed,
            wind: wind,
            botStrokes: botStrokes,
            decor: decor
        )
    }

    /// X coordinate of a mostly-vertical centre line at height y.
    private static func pathX(_ strip: FairwayStrip, atY y: Double) -> Double? {
        let pts = strip.points
        guard pts.count > 1 else { return nil }
        for i in 0..<(pts.count - 1) {
            let a = pts[i]
            let b = pts[i + 1]
            let lo = min(a.y, b.y)
            let hi = max(a.y, b.y)
            if y >= lo && y <= hi && hi - lo > 0.01 {
                return lerpD(a.x, b.x, (y - a.y) / (b.y - a.y))
            }
        }
        return nil
    }

    private static let holeNames: [HoleArchetype: [String]] = [
        .straight: ["The Runway", "Long Lane", "Morning Stroll", "Straight Talk", "Avenue"],
        .doglegLeft: ["The Elbow", "Left Hook", "Hairpin", "Crooked Mile"],
        .doglegRight: ["The Bend", "Right Turn", "Shepherd's Crook", "Fade Away"],
        .waterCrossing: ["Leap of Faith", "The Crossing", "Wet Feet", "Ferry"],
        .islandGreen: ["The Island", "Lonely Shore", "Castaway", "Moat"],
        .bunkerComplex: ["Sandbox", "Pot Luck", "The Trenches", "Beach Party"],
        .narrow: ["The Chute", "Needle's Eye", "Corridor", "Tightrope"],
        .splitFairway: ["Two Roads", "Fork", "Decision", "Crossroads"],
        .elevatedGreen: ["Uphill Battle", "Summit", "The Perch", "Lookout"],
        .mountain: ["Freefall", "Cliff Drop", "Big Sky", "Descent"],
        .coastal: ["Sea Wall", "Cliff Walk", "Salt Air", "Breakers"]
    ]
}
