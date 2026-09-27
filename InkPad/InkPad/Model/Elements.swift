import CoreGraphics
import Foundation

/// An oriented rectangle: used for ellipses, rectangles, images and text.
struct BoxGeometry: Codable, Equatable {
    var center: CGPoint
    var size: CGSize
    var rotation: CGFloat

    init(center: CGPoint, size: CGSize, rotation: CGFloat = 0) {
        self.center = center; self.size = size; self.rotation = rotation
    }

    init(rect: CGRect) {
        self.init(center: rect.center, size: rect.size, rotation: 0)
    }

    /// Maps box-local coordinates (origin at the center) to page coordinates.
    var transform: CGAffineTransform {
        CGAffineTransform(translationX: center.x, y: center.y).rotated(by: rotation)
    }

    var localRect: CGRect {
        CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
    }

    var corners: [CGPoint] { localRect.corners.map { $0.applying(transform) } }

    var boundingRect: CGRect { CGRect.bounding(corners) }

    func contains(_ p: CGPoint, tolerance: CGFloat = 0) -> Bool {
        let local = p.applying(transform.inverted())
        return localRect.expanded(by: tolerance).contains(local)
    }

    /// Applies an arbitrary affine transform. Exact for similarity transforms
    /// and for axis-aligned scaling of unrotated boxes; otherwise the closest
    /// oriented box is produced.
    func applying(_ t: CGAffineTransform) -> BoxGeometry {
        let c = center.applying(t)
        let u = t.applyToVector(CGPoint.unit(angle: rotation) * (size.width / 2))
        let v = t.applyToVector(CGPoint.unit(angle: rotation).perpendicular * (size.height / 2))
        let ul = u.length
        guard ul > 1e-9 else { return BoxGeometry(center: c, size: .zero, rotation: rotation) }
        let w = 2 * ul
        let h = 2 * abs(u.cross(v)) / ul
        return BoxGeometry(center: c, size: CGSize(width: w, height: h), rotation: atan2(u.y, u.x))
    }
}

// MARK: - Shapes

enum ShapeGeometry: Codable, Equatable {
    case line(start: CGPoint, end: CGPoint)
    case ellipse(BoxGeometry)
    case rectangle(BoxGeometry)
    case polygon(points: [CGPoint], closed: Bool)
    /// Chain of cubic Béziers: p0, c1, c2, p1, c1, c2, p2, …  (count = 3n + 1)
    case curve(points: [CGPoint])

    func applying(_ t: CGAffineTransform) -> ShapeGeometry {
        switch self {
        case let .line(s, e): return .line(start: s.applying(t), end: e.applying(t))
        case let .ellipse(b): return .ellipse(b.applying(t))
        case let .rectangle(b): return .rectangle(b.applying(t))
        case let .polygon(pts, closed): return .polygon(points: pts.map { $0.applying(t) }, closed: closed)
        case let .curve(pts): return .curve(points: pts.map { $0.applying(t) })
        }
    }

    var isClosed: Bool {
        switch self {
        case .ellipse, .rectangle: return true
        case let .polygon(_, closed): return closed
        case .line, .curve: return false
        }
    }
}

struct ArrowHeads: Codable, Equatable {
    var start = false
    var end = false
    static let none = ArrowHeads()
}

struct ShapeStyle: Codable, Hashable {
    var strokeColor: RGBAColor
    var lineWidth: CGFloat
    var opacity: CGFloat
    var fillColor: RGBAColor?
    var lineStyle: LineStyle

    init(strokeColor: RGBAColor = .black, lineWidth: CGFloat = 2, opacity: CGFloat = 1,
         fillColor: RGBAColor? = nil, lineStyle: LineStyle = .solid) {
        self.strokeColor = strokeColor; self.lineWidth = lineWidth; self.opacity = opacity
        self.fillColor = fillColor; self.lineStyle = lineStyle
    }
}

struct ShapeElement: Identifiable, Codable {
    var id: UUID = UUID()
    var geometry: ShapeGeometry
    var style: ShapeStyle
    var arrows: ArrowHeads = .none

    var arrowHeadLength: CGFloat { max(10, style.lineWidth * 4.5) }

    var displayName: String {
        switch geometry {
        case .line: return arrows.start || arrows.end ? "Arrow" : "Line"
        case let .ellipse(b): return abs(b.size.width - b.size.height) < 0.5 ? "Circle" : "Ellipse"
        case let .rectangle(b): return abs(b.size.width - b.size.height) < 0.5 ? "Square" : "Rectangle"
        case let .polygon(pts, closed):
            guard closed else { return "Polyline" }
            switch pts.count {
            case 3: return "Triangle"
            case 4: return "Quadrilateral"
            case 5: return "Pentagon"
            case 6: return "Hexagon"
            default: return "Polygon"
            }
        case .curve: return "Curve"
        }
    }

    /// Centerline path in page coordinates (arrow shafts are shortened so the
    /// head tip stays sharp).
    func path(trimForArrows: Bool = true) -> CGPath {
        let p = CGMutablePath()
        switch geometry {
        case var .line(s, e):
            if trimForArrows {
                let dir = (e - s).normalized
                let len = s.distance(to: e)
                let trim = min(arrowHeadLength * 0.6, len * 0.4)
                if arrows.end { e = e - dir * trim }
                if arrows.start { s = s + dir * trim }
            }
            p.move(to: s)
            p.addLine(to: e)
        case let .ellipse(b):
            var t = b.transform
            p.addPath(CGPath(ellipseIn: b.localRect, transform: &t))
        case let .rectangle(b):
            var t = b.transform
            p.addPath(CGPath(rect: b.localRect, transform: &t))
        case let .polygon(pts, closed):
            guard let first = pts.first else { break }
            p.move(to: first)
            for q in pts.dropFirst() { p.addLine(to: q) }
            if closed { p.closeSubpath() }
        case let .curve(pts):
            guard let first = pts.first else { break }
            p.move(to: first)
            var i = 1
            while i + 2 < pts.count {
                p.addCurve(to: pts[i + 2], control1: pts[i], control2: pts[i + 1])
                i += 3
            }
            if i < pts.count { for q in pts[i...] { p.addLine(to: q) } }
        }
        return p
    }

    /// Triangles for arrow heads (tip first).
    var arrowHeadTriangles: [[CGPoint]] {
        guard case let .line(s, e) = geometry, s.distance(to: e) > 0.5 else { return [] }
        var result: [[CGPoint]] = []
        func head(tip: CGPoint, from: CGPoint) -> [CGPoint] {
            let dir = (tip - from).normalized
            let len = min(arrowHeadLength, tip.distance(to: from) * 0.6)
            let base = tip - dir * len
            let half = len * 0.5
            return [tip, base + dir.perpendicular * half, base - dir.perpendicular * half]
        }
        if arrows.end { result.append(head(tip: e, from: s)) }
        if arrows.start { result.append(head(tip: s, from: e)) }
        return result
    }

    var bounds: CGRect {
        var r = path(trimForArrows: false).boundingBoxOfPath
        for tri in arrowHeadTriangles { r = r.union(CGRect.bounding(tri)) }
        return r.expanded(by: style.lineWidth / 2 + 1)
    }

    func transformed(by t: CGAffineTransform) -> ShapeElement {
        var s = self
        s.geometry = geometry.applying(t)
        return s
    }

    func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        guard bounds.expanded(by: tolerance).contains(p) else { return false }
        let centerline = path(trimForArrows: false)
        if style.fillColor != nil, geometry.isClosed, centerline.contains(p) { return true }
        let outline = centerline.copy(strokingWithWidth: style.lineWidth + 2 * tolerance,
                                      lineCap: .round, lineJoin: .round, miterLimit: 10)
        if outline.contains(p) { return true }
        return arrowHeadTriangles.contains { Geometry.polygonContains($0, p) }
    }

    /// Flattened outline polylines, sampled at roughly `spacing`.
    func polylines(spacing: CGFloat = 2) -> [[CGPoint]] {
        path(trimForArrows: false).flattened(spacing: spacing)
    }

    func intersects(path swept: [CGPoint], radius: CGFloat) -> Bool {
        guard !swept.isEmpty, bounds.intersects(CGRect.bounding(swept).expanded(by: radius)) else { return false }
        let tol = radius + style.lineWidth / 2
        for line in polylines(spacing: max(1, radius)) {
            for q in line where Geometry.distance(from: q, toPolyline: swept) <= tol { return true }
        }
        if style.fillColor != nil, geometry.isClosed {
            let outline = path(trimForArrows: false)
            if swept.contains(where: { outline.contains($0) }) { return true }
        }
        return false
    }

    /// Points used for magnetic snapping of new shapes.
    var keyPoints: [CGPoint] {
        switch geometry {
        case let .line(s, e): return [s, e]
        case let .rectangle(b): return b.corners + [b.center]
        case let .ellipse(b):
            let t = b.transform
            return [b.center] + [CGPoint(x: b.size.width / 2, y: 0), CGPoint(x: -b.size.width / 2, y: 0),
                                 CGPoint(x: 0, y: b.size.height / 2), CGPoint(x: 0, y: -b.size.height / 2)].map { $0.applying(t) }
        case let .polygon(pts, _): return pts
        case let .curve(pts): return [pts.first, pts.last].compactMap { $0 }
        }
    }

    /// Converts the outline to plain ink strokes (used by the pixel eraser).
    func asStrokes() -> [Stroke] {
        let style = StrokeStyle(kind: .fineliner, color: self.style.strokeColor, width: self.style.lineWidth,
                                opacity: self.style.opacity, pressureSensitivity: 0, lineStyle: self.style.lineStyle)
        var lines = polylines(spacing: 1.5)
        for tri in arrowHeadTriangles { lines.append(tri + [tri[0]]) }
        return lines.filter { $0.count > 1 }.map { line in
            Stroke(points: line.map { InkPoint(location: $0) }, style: style)
        }
    }
}

extension CGPath {
    /// Flattens the path into polylines with at most `spacing` between samples on curves.
    func flattened(spacing: CGFloat) -> [[CGPoint]] {
        var result: [[CGPoint]] = []
        var current: [CGPoint] = []
        var start = CGPoint.zero
        var last = CGPoint.zero
        func flush() { if current.count > 0 { result.append(current) }; current = [] }
        applyWithBlock { elementPtr in
            let e = elementPtr.pointee
            switch e.type {
            case .moveToPoint:
                flush()
                last = e.points[0]; start = last
                current = [last]
            case .addLineToPoint:
                let p = e.points[0]
                let n = max(1, Int(ceil(last.distance(to: p) / spacing)))
                for i in 1...n { current.append(last.lerp(to: p, t: CGFloat(i) / CGFloat(n))) }
                last = p
            case .addQuadCurveToPoint:
                let c = e.points[0], p = e.points[1]
                let n = max(2, Int(ceil((last.distance(to: c) + c.distance(to: p)) / spacing)))
                let p0 = last
                for i in 1...n {
                    let t = CGFloat(i) / CGFloat(n), mt = 1 - t
                    current.append(p0 * (mt * mt) + c * (2 * mt * t) + p * (t * t))
                }
                last = p
            case .addCurveToPoint:
                let c1 = e.points[0], c2 = e.points[1], p = e.points[2]
                let n = max(2, Int(ceil((last.distance(to: c1) + c1.distance(to: c2) + c2.distance(to: p)) / spacing)))
                let p0 = last
                for i in 1...n {
                    let t = CGFloat(i) / CGFloat(n), mt = 1 - t
                    let a = p0 * (mt * mt * mt) + c1 * (3 * mt * mt * t)
                    current.append(a + c2 * (3 * mt * t * t) + p * (t * t * t))
                }
                last = p
            case .closeSubpath:
                if last.distance(to: start) > 0.01 {
                    let n = max(1, Int(ceil(last.distance(to: start) / spacing)))
                    for i in 1...n { current.append(last.lerp(to: start, t: CGFloat(i) / CGFloat(n))) }
                }
                last = start
            @unknown default:
                break
            }
        }
        flush()
        return result
    }
}

// MARK: - Images

struct ImageElement: Identifiable, Codable {
    var id: UUID = UUID()
    /// File name inside the document's assets folder.
    var assetName: String
    var box: BoxGeometry
    var opacity: CGFloat = 1

    var bounds: CGRect { box.boundingRect }

    func transformed(by t: CGAffineTransform) -> ImageElement {
        var e = self
        e.box = box.applying(t)
        return e
    }
}

// MARK: - Text

enum TextAlignmentOption: String, Codable, CaseIterable, Identifiable {
    case left, center, right, justified
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .left: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        case .justified: return "text.justify"
        }
    }
}

struct TextStyle: Codable, Hashable {
    /// Font family name, or `TextStyle.systemFamily` for San Francisco.
    var fontFamily: String = TextStyle.systemFamily
    var fontSize: CGFloat = 18
    var color: RGBAColor = .black
    var bold = false
    var italic = false
    var alignment: TextAlignmentOption = .left

    static let systemFamily = "System"
    static let availableFamilies = [
        systemFamily, "New York", "Helvetica Neue", "Avenir Next", "Georgia",
        "Times New Roman", "Menlo", "Courier New", "Noteworthy", "Marker Felt", "Chalkboard SE",
    ]
}

struct TextElement: Identifiable, Codable {
    var id: UUID = UUID()
    var text: String
    var style: TextStyle
    /// `size.width` is the wrapping width; height is derived from layout.
    var box: BoxGeometry

    var bounds: CGRect { box.boundingRect.expanded(by: 1) }

    func transformed(by t: CGAffineTransform) -> TextElement {
        var e = self
        e.box = box.applying(t)
        e.style.fontSize = max(4, style.fontSize * t.scaleFactor)
        return e
    }
}
