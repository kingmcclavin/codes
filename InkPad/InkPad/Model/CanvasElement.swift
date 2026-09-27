import CoreGraphics
import Foundation

/// Everything that can live on a page. New element types are added here and
/// in `ElementRenderer`; the canvas engine itself is type-agnostic.
enum CanvasElement: Identifiable {
    case stroke(Stroke)
    case shape(ShapeElement)
    case image(ImageElement)
    case text(TextElement)

    var id: UUID {
        switch self {
        case let .stroke(s): return s.id
        case let .shape(s): return s.id
        case let .image(i): return i.id
        case let .text(t): return t.id
        }
    }

    /// Conservative render bounds in page coordinates.
    var bounds: CGRect {
        switch self {
        case let .stroke(s): return s.bounds
        case let .shape(s): return s.bounds
        case let .image(i): return i.bounds
        case let .text(t): return t.bounds
        }
    }

    var kindName: String {
        switch self {
        case let .stroke(s): return s.style.isHighlighter ? "Highlight" : "Ink"
        case let .shape(s): return s.displayName
        case .image: return "Image"
        case .text: return "Text"
        }
    }

    var isStroke: Bool { if case .stroke = self { return true }; return false }
    var isShape: Bool { if case .shape = self { return true }; return false }

    /// Oriented box for elements that have one (used for single-selection handles).
    var box: BoxGeometry? {
        switch self {
        case let .image(i): return i.box
        case let .text(t): return t.box
        case let .shape(s):
            switch s.geometry {
            case let .rectangle(b), let .ellipse(b): return b
            default: return nil
            }
        case .stroke: return nil
        }
    }

    func transformed(by t: CGAffineTransform) -> CanvasElement {
        switch self {
        case let .stroke(s): return .stroke(s.transformed(by: t))
        case let .shape(s): return .shape(s.transformed(by: t))
        case let .image(i): return .image(i.transformed(by: t))
        case let .text(x): return .text(x.transformed(by: t))
        }
    }

    func withNewID() -> CanvasElement {
        switch self {
        case var .stroke(s): s.id = UUID(); return .stroke(s)
        case var .shape(s): s.id = UUID(); return .shape(s)
        case var .image(i): i.id = UUID(); return .image(i)
        case var .text(t): t.id = UUID(); return .text(t)
        }
    }

    func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        switch self {
        case let .stroke(s): return s.hitTest(p, tolerance: tolerance)
        case let .shape(s): return s.hitTest(p, tolerance: tolerance)
        case let .image(i): return i.box.contains(p, tolerance: tolerance)
        case let .text(t): return t.box.contains(p, tolerance: tolerance)
        }
    }

    /// Whether a circle of `radius` swept along `path` touches the element.
    func intersects(path: [CGPoint], radius: CGFloat) -> Bool {
        switch self {
        case let .stroke(s): return s.intersects(path: path, radius: radius)
        case let .shape(s): return s.intersects(path: path, radius: radius)
        case let .image(i): return path.contains { i.box.contains($0, tolerance: radius) }
        case let .text(t): return path.contains { t.box.contains($0, tolerance: radius) }
        }
    }

    /// Representative sample points used for lasso / region containment.
    var samplePoints: [CGPoint] {
        switch self {
        case let .stroke(s):
            let pts = s.locations
            if pts.count <= 64 { return pts }
            let step = Double(pts.count) / 64
            return (0..<64).map { pts[Int(Double($0) * step)] }
        case let .shape(s):
            return s.polylines(spacing: max(4, s.bounds.diagonal / 48)).flatMap { $0 }
        case let .image(i): return i.box.corners + [i.box.center]
        case let .text(t): return t.box.corners + [t.box.center]
        }
    }

    /// Lasso containment: most of the element must be inside the polygon.
    func isEnclosed(by polygon: [CGPoint]) -> Bool {
        let samples = samplePoints
        guard !samples.isEmpty else { return false }
        let inside = samples.reduce(0) { $0 + (Geometry.polygonContains(polygon, $1) ? 1 : 0) }
        switch self {
        case .stroke: return Double(inside) / Double(samples.count) >= 0.6
        case .shape: return Double(inside) / Double(samples.count) >= 0.75
        case let .image(i): return Geometry.polygonContains(polygon, i.box.center) && inside >= 3
        case let .text(t): return Geometry.polygonContains(polygon, t.box.center) && inside >= 3
        }
    }

    var supportsColor: Bool {
        switch self {
        case .image: return false
        default: return true
        }
    }

    var primaryColor: RGBAColor? {
        switch self {
        case let .stroke(s): return s.style.color
        case let .shape(s): return s.style.strokeColor
        case let .text(t): return t.style.color
        case .image: return nil
        }
    }

    func recolored(_ color: RGBAColor) -> CanvasElement {
        switch self {
        case var .stroke(s): s.style.color = color; return .stroke(s)
        case var .shape(s): s.style.strokeColor = color; return .shape(s)
        case var .text(t): t.style.color = color; return .text(t)
        case .image: return self
        }
    }
}

extension CanvasElement: Codable {
    private enum CodingKeys: String, CodingKey { case type, stroke, shape, image, text }
    private enum Kind: String, Codable { case stroke, shape, image, text }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .stroke: self = .stroke(try c.decode(Stroke.self, forKey: .stroke))
        case .shape: self = .shape(try c.decode(ShapeElement.self, forKey: .shape))
        case .image: self = .image(try c.decode(ImageElement.self, forKey: .image))
        case .text: self = .text(try c.decode(TextElement.self, forKey: .text))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .stroke(s): try c.encode(Kind.stroke, forKey: .type); try c.encode(s, forKey: .stroke)
        case let .shape(s): try c.encode(Kind.shape, forKey: .type); try c.encode(s, forKey: .shape)
        case let .image(i): try c.encode(Kind.image, forKey: .type); try c.encode(i, forKey: .image)
        case let .text(t): try c.encode(Kind.text, forKey: .type); try c.encode(t, forKey: .text)
        }
    }
}
