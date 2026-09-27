import CoreGraphics
import Foundation

enum InkKind: String, Codable, CaseIterable, Identifiable {
    case fineliner, ballpoint, fountain, marker, pencil, highlighter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fineliner: return "Fine Pen"
        case .ballpoint: return "Ballpoint"
        case .fountain: return "Fountain Pen"
        case .marker: return "Marker"
        case .pencil: return "Pencil"
        case .highlighter: return "Highlighter"
        }
    }

    var symbol: String {
        switch self {
        case .fineliner: return "pencil.tip"
        case .ballpoint: return "pencil"
        case .fountain: return "pencil.and.scribble"
        case .marker: return "paintbrush.pointed"
        case .pencil: return "pencil.line"
        case .highlighter: return "highlighter"
        }
    }

    /// Quick-pick widths offered in the tool bar.
    var quickWidths: [CGFloat] {
        switch self {
        case .fineliner: return [0.6, 1.2, 2.0]
        case .ballpoint, .fountain: return [1.0, 1.8, 3.0]
        case .pencil: return [1.0, 2.0, 4.0]
        case .marker: return [3, 6, 10]
        case .highlighter: return [10, 16, 26]
        }
    }

    var widthRange: ClosedRange<CGFloat> {
        switch self {
        case .highlighter: return 4...48
        case .marker: return 1...36
        default: return 0.3...24
        }
    }
}

enum LineStyle: String, Codable, CaseIterable, Identifiable {
    case solid, dashed, dotted
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    func dashPattern(width: CGFloat) -> [CGFloat]? {
        switch self {
        case .solid: return nil
        case .dashed: return [max(4, width * 3.5), max(3, width * 2.5)]
        case .dotted: return [0.001, max(2.5, width * 2.2)]
        }
    }
}

/// A single input sample. Stored compactly (Float32) since documents may hold
/// hundreds of thousands of samples.
struct InkPoint: Equatable {
    var x: Float
    var y: Float
    /// Normalized pressure in 0...1 (0.25 ≈ a normal writing force).
    var force: Float
    /// Pencil altitude in radians (π/2 = perpendicular to the screen).
    var altitude: Float
    /// Pencil azimuth in radians.
    var azimuth: Float
    /// Seconds since the start of the stroke.
    var t: Float

    init(location: CGPoint, force: CGFloat = 0.25, altitude: CGFloat = .pi / 2, azimuth: CGFloat = 0, t: TimeInterval = 0) {
        x = Float(location.x); y = Float(location.y)
        self.force = Float(force); self.altitude = Float(altitude); self.azimuth = Float(azimuth); self.t = Float(t)
    }

    var location: CGPoint {
        get { CGPoint(x: CGFloat(x), y: CGFloat(y)) }
        set { x = Float(newValue.x); y = Float(newValue.y) }
    }

    func interpolated(to o: InkPoint, t f: Float) -> InkPoint {
        var p = self
        p.x += (o.x - x) * f
        p.y += (o.y - y) * f
        p.force += (o.force - force) * f
        p.altitude += (o.altitude - altitude) * f
        p.azimuth += (o.azimuth - azimuth) * f
        p.t += (o.t - t) * f
        return p
    }
}

struct StrokeStyle: Codable, Hashable {
    var kind: InkKind
    var color: RGBAColor
    /// Nominal width in points at normal pressure.
    var width: CGFloat
    var opacity: CGFloat
    /// 0 = constant width, 1 = fully pressure driven.
    var pressureSensitivity: CGFloat
    /// 0 = ignore tilt, 1 = strong shading when the pencil is tilted.
    var tiltSensitivity: CGFloat
    var lineStyle: LineStyle

    init(kind: InkKind, color: RGBAColor, width: CGFloat, opacity: CGFloat = 1,
         pressureSensitivity: CGFloat = 0.5, tiltSensitivity: CGFloat = 0, lineStyle: LineStyle = .solid) {
        self.kind = kind; self.color = color; self.width = width; self.opacity = opacity
        self.pressureSensitivity = pressureSensitivity; self.tiltSensitivity = tiltSensitivity; self.lineStyle = lineStyle
    }

    var isHighlighter: Bool { kind == .highlighter }

    /// Width multiplier for a normalized force. Calibrated so a typical
    /// writing force (~0.25) gives ≈1×.
    static func pressureFactor(_ force: CGFloat) -> CGFloat {
        (0.35 + 1.5 * pow(force.clamped(0, 1), 0.6)).clamped(0.3, 1.9)
    }

    func width(at p: InkPoint) -> CGFloat {
        var w = width
        if pressureSensitivity > 0 {
            let f = StrokeStyle.pressureFactor(CGFloat(p.force))
            w *= 1 + (f - 1) * pressureSensitivity
        }
        if tiltSensitivity > 0 {
            let alt = CGFloat(p.altitude)
            let tilt = (1 - (alt / (.pi / 3)).clamped(0, 1))   // 0 when steeper than 60°
            w *= 1 + tilt * 2.5 * tiltSensitivity
        }
        return max(0.15, w)
    }

    /// Largest width any sample can produce, used for conservative bounds.
    var maximumWidth: CGFloat {
        width * (1 + 0.9 * pressureSensitivity) * (1 + 2.5 * tiltSensitivity)
    }
}

/// Vector handwriting stroke. Points are kept verbatim (no rasterization) so
/// the stroke can be re-rendered at any zoom, partially erased, transformed,
/// and restyled.
struct Stroke: Identifiable {
    var id: UUID
    var points: [InkPoint] { didSet { recomputeBounds() } }
    var style: StrokeStyle { didSet { recomputeBounds() } }
    var createdAt: Date
    private(set) var bounds: CGRect = .null

    init(id: UUID = UUID(), points: [InkPoint], style: StrokeStyle, createdAt: Date = Date()) {
        self.id = id
        self.points = points
        self.style = style
        self.createdAt = createdAt
        recomputeBounds()
    }

    var locations: [CGPoint] { points.map(\.location) }

    private mutating func recomputeBounds() {
        guard let first = points.first else { bounds = .null; return }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        var maxW: CGFloat = 0
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
            maxW = max(maxW, style.width(at: p))
        }
        let pad = maxW / 2 + 1
        bounds = CGRect(x: CGFloat(minX), y: CGFloat(minY), width: CGFloat(maxX - minX), height: CGFloat(maxY - minY))
            .insetBy(dx: -pad, dy: -pad)
    }

    func transformed(by t: CGAffineTransform) -> Stroke {
        var s = self
        let rot = Float(t.rotationAngle)
        s.points = points.map { p in
            var q = p
            q.location = p.location.applying(t)
            q.azimuth = p.azimuth + rot
            return q
        }
        s.style.width = style.width * t.scaleFactor
        return s
    }

    /// Distance-based hit test against the stroke centerline.
    func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        guard bounds.expanded(by: tolerance).contains(p) else { return false }
        let pts = locations
        if pts.count == 1 { return pts[0].distance(to: p) <= style.width / 2 + tolerance }
        for i in 1..<pts.count {
            let w = max(style.width(at: points[i - 1]), style.width(at: points[i]))
            if Geometry.distance(from: p, toSegment: pts[i - 1], pts[i]) <= w / 2 + tolerance { return true }
        }
        return false
    }

    /// Whether a swept circle along `path` touches this stroke.
    func intersects(path: [CGPoint], radius: CGFloat) -> Bool {
        guard !path.isEmpty else { return false }
        let pathBounds = CGRect.bounding(path).expanded(by: radius)
        guard bounds.intersects(pathBounds) else { return false }
        let pts = locations
        let tol = radius + style.width / 2
        if path.count == 1 { return hitTest(path[0], tolerance: radius) }
        if pts.count == 1 { return Geometry.distance(from: pts[0], toPolyline: path) <= tol }
        for i in 1..<path.count {
            let a = path[i - 1], b = path[i]
            let segBox = CGRect.bounding([a, b]).expanded(by: tol)
            guard segBox.intersects(bounds) else { continue }
            for k in 1..<pts.count {
                let p0 = pts[k - 1], p1 = pts[k]
                if max(p0.x, p1.x) < segBox.minX || min(p0.x, p1.x) > segBox.maxX
                    || max(p0.y, p1.y) < segBox.minY || min(p0.y, p1.y) > segBox.maxY { continue }
                if Geometry.distance(segment: a, b, segment: p0, p1) <= tol { return true }
            }
        }
        return false
    }
}

// MARK: - Compact Codable representation

extension Stroke: Codable {
    private enum CodingKeys: String, CodingKey { case id, style, createdAt, points }

    private static let floatsPerPoint = 6

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        let style = try c.decode(StrokeStyle.self, forKey: .style)
        let createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        let data = try c.decode(Data.self, forKey: .points)
        self.init(id: id, points: Stroke.unpack(data), style: style, createdAt: createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(style, forKey: .style)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(Stroke.pack(points), forKey: .points)
    }

    /// Packs points as little-endian Float32 tuples.
    static func pack(_ points: [InkPoint]) -> Data {
        var floats = [UInt32]()
        floats.reserveCapacity(points.count * floatsPerPoint)
        for p in points {
            floats.append(p.x.bitPattern.littleEndian)
            floats.append(p.y.bitPattern.littleEndian)
            floats.append(p.force.bitPattern.littleEndian)
            floats.append(p.altitude.bitPattern.littleEndian)
            floats.append(p.azimuth.bitPattern.littleEndian)
            floats.append(p.t.bitPattern.littleEndian)
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func unpack(_ data: Data) -> [InkPoint] {
        let count = data.count / (MemoryLayout<UInt32>.size * floatsPerPoint)
        var result = [InkPoint]()
        result.reserveCapacity(count)
        data.withUnsafeBytes { raw in
            for i in 0..<count {
                let base = i * floatsPerPoint * 4
                func f(_ k: Int) -> Float {
                    Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: base + k * 4, as: UInt32.self)))
                }
                var p = InkPoint(location: .zero)
                p.x = f(0); p.y = f(1); p.force = f(2); p.altitude = f(3); p.azimuth = f(4); p.t = f(5)
                result.append(p)
            }
        }
        return result
    }
}
