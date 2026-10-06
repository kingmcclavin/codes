import Compression
import CoreGraphics
import Foundation

/// Best-effort import of GoodNotes 6 `.goodnotes` files.
///
/// The format isn't documented; this reads what's been worked out from real
/// files: a zip of protobuf logs. Pages, their paper (the template PDF),
/// pen and highlighter strokes (as editable Basis ink) and images come
/// across. Typed text boxes and other objects are skipped.
enum GoodNotesImporter {
    enum ImportError: LocalizedError {
        case notGoodNotes, noPages
        var errorDescription: String? {
            switch self {
            case .notGoodNotes: return "This doesn't look like a GoodNotes file."
            case .noPages: return "No pages could be read from this GoodNotes file."
            }
        }
    }

    struct Result {
        var archive: NotebookArchive
        var strokes = 0
        var images = 0
        var skipped = 0
    }

    static func importFile(at url: URL) throws -> Result {
        let zip = try ZipReader(data: Data(contentsOf: url))
        return try convert(zip: zip, fallbackTitle: url.deletingPathExtension().lastPathComponent)
    }

    // MARK: Conversion

    private struct Template { var attachment: String?; var size: CGSize; var pageIndex: Int }
    private struct GNPage { var id: String; var template: String?; var order: String }

    static func convert(zip: ZipReader, fallbackTitle: String) throws -> Result {
        guard let events = zip.file("index.events.pb") else { throw ImportError.notGoodNotes }
        var title = fallbackTitle
        var templates: [String: Template] = [:]
        var pages: [String: GNPage] = [:]
        var deleted = Set<String>()

        for message in Protobuf.delimited(events) {
            let fields = Protobuf.fields(message)
            for f in fields {
                guard let body = f.bytes else { continue }
                let m = Protobuf.fields(body)
                switch f.number {
                case 30:  // document: 2.1 = title
                    if let t = m.message(2)?.string(1), !t.isEmpty { title = t }
                case 2:   // page template (paper)
                    guard let id = m.string(2) else { continue }
                    let size = m.message(8)
                    let w = size?.float(1) ?? 612, h = size?.float(2) ?? 792
                    templates[id] = Template(attachment: m.string(4), size: CGSize(width: CGFloat(w), height: CGFloat(h)),
                                             pageIndex: max(0, Int(m.varint(5) ?? 1) - 1))
                case 54:  // page
                    guard let id = m.string(2) else { continue }
                    pages[id] = GNPage(id: id, template: m.message(3)?.string(1), order: m.message(4)?.string(1) ?? id)
                case 56:  // page deleted
                    if let id = m.string(2) { deleted.insert(id) }
                default:
                    break
                }
            }
        }

        let ordered = pages.values.filter { !deleted.contains($0.id) }.sorted { $0.order < $1.order }
        guard !ordered.isEmpty else { throw ImportError.noPages }

        var result = Result(archive: NotebookArchive(manifest: DocumentManifest(
            id: UUID(), title: title, createdAt: Date(), modifiedAt: Date(), pageIDs: [], firstPageSize: .zero,
            toolSettings: ToolSettings(), viewState: ViewState()), pages: [], assets: [:]))

        for gn in ordered {
            let template = gn.template.flatMap { templates[$0] }
            let size = template?.size ?? CGSize(width: 612, height: 792)
            var background = PageBackground()
            if let att = template?.attachment, let pdf = zip.file("attachments/\(att)"), pdf.starts(with: Data("%PDF".utf8)) {
                let name = "gn-\(att).pdf"
                result.archive.assets[name] = pdf
                background.pdf = PDFPageSource(assetName: name, pageIndex: template?.pageIndex ?? 0)
            }
            var page = PageData(size: size, background: background)
            if let notesID = incrementedUUID(gn.id), let notes = zip.file("notes/\(notesID)") {
                page.elements = elements(fromNotes: notes, zip: zip, result: &result)
            }
            result.archive.pages.append(page)
        }
        result.archive.manifest.pageIDs = result.archive.pages.map(\.id)
        result.archive.manifest.firstPageSize = result.archive.pages[0].size
        return result
    }

    /// A page's ink lives in `notes/<page id + 1>`.
    static func incrementedUUID(_ s: String) -> String? {
        guard let u = UUID(uuidString: s) else { return nil }
        var bytes = withUnsafeBytes(of: u.uuid) { Array($0) }
        for i in stride(from: 15, through: 0, by: -1) {
            bytes[i] &+= 1
            if bytes[i] != 0 { break }
        }
        let t = (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                 bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: t).uuidString
    }

    /// Notes files are logs of (header, body) records. A header with field 3
    /// set marks an erased object; the last record for an id wins.
    private static func elements(fromNotes data: Data, zip: ZipReader, result: inout Result) -> [CanvasElement] {
        var order: [String] = []
        var latest: [String: CanvasElement] = [:]
        var erased = Set<String>()
        for message in Protobuf.delimited(data) {
            let fields = Protobuf.fields(message)
            if let id = fields.string(1), fields.message(2) != nil {   // header
                if (fields.varint(3) ?? 0) != 0 { erased.insert(id) } else { erased.remove(id) }
                continue
            }
            if let body = fields.message(7), let id = body.string(1) {   // stroke
                if let stroke = stroke(from: body) {
                    if latest[id] == nil { order.append(id) }
                    latest[id] = .stroke(stroke)
                } else {
                    erased.insert(id)
                }
            } else if let body = fields.message(1), let id = body.string(1), let attachment = body.string(4) {   // image
                guard let rect = body.message(2), let origin = rect.message(1), let size = rect.message(2),
                      let file = zip.file("attachments/\(attachment)") else { result.skipped += 1; continue }
                let ext = file.starts(with: Data([0x89, 0x50, 0x4E, 0x47])) ? "png" : "jpg"
                let name = "gn-\(attachment).\(ext)"
                result.archive.assets[name] = file
                let frame = CGRect(x: CGFloat(origin.float(1) ?? 0), y: CGFloat(origin.float(2) ?? 0),
                                   width: CGFloat(size.float(1) ?? 100), height: CGFloat(size.float(2) ?? 100))
                if latest[id] == nil { order.append(id) }
                latest[id] = .image(ImageElement(assetName: name, box: BoxGeometry(rect: frame)))
            }
        }
        var out: [CanvasElement] = []
        for id in order where !erased.contains(id) {
            guard let e = latest[id] else { continue }
            switch e {
            case .stroke: result.strokes += 1
            case .image: result.images += 1
            default: break
            }
            out.append(e)
        }
        return out
    }

    /// Stroke body: 2 = compressed geometry, 4 = RGBA colour.
    static func stroke(from body: Protobuf.Fields) -> Stroke? {
        guard let blob = body.bytes(2), let raw = LZ4.decodeAppleFrames(blob),
              let geometry = StrokeGeometry(raw), geometry.points.count >= 1 else { return nil }
        let rgba = body.message(4)
        let r = CGFloat(rgba?.float(1) ?? 0), g = CGFloat(rgba?.float(2) ?? 0), b = CGFloat(rgba?.float(3) ?? 0)
        let a = CGFloat(rgba?.float(4) ?? 1)
        let isHighlighter = a < 0.95 || geometry.width >= 12
        // GoodNotes' adaptive ink is stored near-white when written in dark
        // mode; on white paper that would vanish, so show it as black.
        var color = RGBAColor(r: r, g: g, b: b, a: isHighlighter ? 1 : a)
        if !isHighlighter, 0.299 * r + 0.587 * g + 0.114 * b > 0.9 { color = RGBAColor(r: 0, g: 0, b: 0, a: 1) }
        let style = StrokeStyle(kind: isHighlighter ? .highlighter : .fineliner,
                                color: color,
                                width: max(0.3, geometry.width),
                                opacity: isHighlighter ? max(0.3, a) : 1,
                                pressureSensitivity: 0)
        var points = geometry.points.map { InkPoint(location: $0) }
        if points.count == 1 { points.append(points[0]) }   // a dot
        return Stroke(points: points, style: style)
    }

    /// GoodNotes stroke geometry ("tpl" record): a start point followed by
    /// quadratic segments (control, end), plus the pen width.
    struct StrokeGeometry {
        var width: CGFloat
        var points: [CGPoint]

        init?(_ d: Data) {
            let b = [UInt8](d)
            guard b.count > 12, b[0] == 0x74, b[1] == 0x70, b[2] == 0x6C, b[3] == 0 else { return nil }
            var i = 8
            guard let nul = b[i...].firstIndex(of: 0) else { return nil }
            let signature = String(decoding: b[i..<nul], as: UTF8.self)
            // Only the layout seen in GoodNotes 6 files is understood.
            guard signature.hasPrefix("vuA(v)A(S(uu))A(S(uuuu))") else { return nil }
            i = nul + 1
            func u16() -> Int? { guard i + 2 <= b.count else { return nil }; defer { i += 2 }; return Int(b[i]) | Int(b[i + 1]) << 8 }
            func u32() -> Int? {
                guard i + 4 <= b.count else { return nil }
                defer { i += 4 }
                return Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24
            }
            func f32() -> CGFloat? { u32().map { CGFloat(Float(bitPattern: UInt32($0))) } }

            guard u16() != nil, let w = f32(), let typeCount = u32(), typeCount < 1_000_000 else { return nil }
            i += typeCount * 2
            guard let startCount = u32(), startCount <= 1 else { return nil }
            var pts: [CGPoint] = []
            if startCount == 1 {
                guard let x = f32(), let y = f32() else { return nil }
                pts.append(CGPoint(x: x, y: y))
            }
            guard let segments = u32(), segments < 1_000_000 else { return nil }
            for _ in 0..<segments {
                guard let cx = f32(), let cy = f32(), let ex = f32(), let ey = f32(), let p0 = pts.last else { return nil }
                let c = CGPoint(x: cx, y: cy), e = CGPoint(x: ex, y: ey)
                // Sample the quadratic curve; enough points for smooth ink.
                let steps = max(2, min(12, Int((p0.distance(to: c) + c.distance(to: e)) / 2)))
                for k in 1...steps {
                    let t = CGFloat(k) / CGFloat(steps), mt = 1 - t
                    pts.append(CGPoint(x: mt * mt * p0.x + 2 * mt * t * c.x + t * t * e.x,
                                       y: mt * mt * p0.y + 2 * mt * t * c.y + t * t * e.y))
                }
            }
            guard pts.allSatisfy({ $0.x.isFinite && $0.y.isFinite }), w.isFinite else { return nil }
            width = w
            points = pts
        }
    }
}

// MARK: - Protobuf (just enough to read)

enum Protobuf {
    struct Field {
        var number: Int
        var varint: UInt64?
        var fixed32: UInt32?
        var bytes: Data?
    }

    typealias Fields = [Field]

    /// Messages each prefixed by a varint length.
    static func delimited(_ data: Data) -> [Data] {
        let b = [UInt8](data)
        var i = 0, out: [Data] = []
        while i < b.count, let n = varint(b, &i), n <= UInt64(b.count - i) {
            out.append(Data(b[i..<(i + Int(n))]))
            i += Int(n)
        }
        return out
    }

    static func fields(_ data: Data) -> Fields {
        let b = [UInt8](data)
        var i = 0, out: Fields = []
        while i < b.count {
            guard let key = varint(b, &i) else { break }
            let number = Int(key >> 3)
            guard number > 0 else { break }
            switch key & 7 {
            case 0:
                guard let v = varint(b, &i) else { return out }
                out.append(Field(number: number, varint: v))
            case 1:
                guard i + 8 <= b.count else { return out }
                i += 8
            case 2:
                guard let n = varint(b, &i), n <= UInt64(b.count - i) else { return out }
                out.append(Field(number: number, bytes: Data(b[i..<(i + Int(n))])))
                i += Int(n)
            case 5:
                guard i + 4 <= b.count else { return out }
                let v = UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
                out.append(Field(number: number, fixed32: v))
                i += 4
            default:
                return out
            }
        }
        return out
    }

    static func varint(_ b: [UInt8], _ i: inout Int) -> UInt64? {
        var result: UInt64 = 0, shift: UInt64 = 0
        while i < b.count, shift < 64 {
            let c = b[i]; i += 1
            result |= UInt64(c & 0x7F) << shift
            if c & 0x80 == 0 { return result }
            shift += 7
        }
        return nil
    }
}

extension Array where Element == Protobuf.Field {
    func bytes(_ n: Int) -> Data? { first { $0.number == n && $0.bytes != nil }?.bytes }
    func string(_ n: Int) -> String? { bytes(n).flatMap { String(data: $0, encoding: .utf8) } }
    func message(_ n: Int) -> Protobuf.Fields? { bytes(n).map(Protobuf.fields) }
    func varint(_ n: Int) -> UInt64? { first { $0.number == n && $0.varint != nil }?.varint }
    func float(_ n: Int) -> Float? { first { $0.number == n && $0.fixed32 != nil }?.fixed32.map(Float.init(bitPattern:)) }
}

// MARK: - LZ4 (Apple "bv41" frames)

enum LZ4 {
    static func decodeAppleFrames(_ data: Data) -> Data? {
        let b = [UInt8](data)
        var i = 0
        var out: [UInt8] = []
        func u32(_ at: Int) -> Int { Int(b[at]) | Int(b[at + 1]) << 8 | Int(b[at + 2]) << 16 | Int(b[at + 3]) << 24 }
        while i + 4 <= b.count {
            let magic = String(decoding: b[i..<(i + 4)], as: UTF8.self)
            if magic == "bv4$" { break }
            if magic == "bv41" {
                guard i + 12 <= b.count else { return nil }
                let size = u32(i + 4), compressed = u32(i + 8)
                guard i + 12 + compressed <= b.count, size < 50_000_000,
                      let block = decodeBlock(b[(i + 12)..<(i + 12 + compressed)], expected: size) else { return nil }
                out += block
                i += 12 + compressed
            } else if magic == "bv4-" {
                guard i + 8 <= b.count else { return nil }
                let size = u32(i + 4)
                guard i + 8 + size <= b.count else { return nil }
                out += b[(i + 8)..<(i + 8 + size)]
                i += 8 + size
            } else {
                return nil
            }
        }
        return out.isEmpty ? nil : Data(out)
    }

    static func decodeBlock(_ src: ArraySlice<UInt8>, expected: Int) -> [UInt8]? {
        var out: [UInt8] = []
        out.reserveCapacity(expected)
        var i = src.startIndex
        while i < src.endIndex {
            let token = src[i]; i += 1
            var literal = Int(token >> 4)
            if literal == 15 {
                while i < src.endIndex { let x = Int(src[i]); i += 1; literal += x; if x != 255 { break } }
            }
            guard i + literal <= src.endIndex else { return nil }
            out += src[i..<(i + literal)]
            i += literal
            if i >= src.endIndex { break }
            guard i + 2 <= src.endIndex else { return nil }
            let offset = Int(src[i]) | Int(src[i + 1]) << 8
            i += 2
            var match = Int(token & 15)
            if match == 15 {
                while i < src.endIndex { let x = Int(src[i]); i += 1; match += x; if x != 255 { break } }
            }
            match += 4
            guard offset > 0, offset <= out.count, out.count + match <= expected else { return nil }
            let start = out.count - offset
            for k in 0..<match { out.append(out[start + k]) }
        }
        return out
    }
}

// MARK: - Zip

/// Minimal zip reader (stored and deflate entries) using Apple's Compression.
struct ZipReader {
    private var entries: [String: (offset: Int, method: Int, compressed: Int, size: Int)] = [:]
    private let bytes: [UInt8]

    enum ZipError: Error { case invalid }

    init(data: Data) throws {
        bytes = [UInt8](data)
        let b = bytes
        func u16(_ at: Int) -> Int { Int(b[at]) | Int(b[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        // End of central directory record.
        guard b.count >= 22 else { throw ZipError.invalid }
        var eocd = -1
        var k = b.count - 22
        while k >= max(0, b.count - 65_557) {
            if b[k] == 0x50, b[k + 1] == 0x4B, b[k + 2] == 0x05, b[k + 3] == 0x06 { eocd = k; break }
            k -= 1
        }
        guard eocd >= 0 else { throw ZipError.invalid }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        for _ in 0..<count {
            guard p + 46 <= b.count, u32(p) == 0x02014B50 else { throw ZipError.invalid }
            let method = u16(p + 10), compressed = u32(p + 20), size = u32(p + 24)
            let nameLength = u16(p + 28), extra = u16(p + 30), comment = u16(p + 32)
            let local = u32(p + 42)
            guard p + 46 + nameLength <= b.count else { throw ZipError.invalid }
            let name = String(decoding: b[(p + 46)..<(p + 46 + nameLength)], as: UTF8.self)
            entries[name] = (local, method, compressed, size)
            p += 46 + nameLength + extra + comment
        }
    }

    var names: [String] { Array(entries.keys) }

    func file(_ name: String) -> Data? {
        guard let e = entries[name], e.offset + 30 <= bytes.count else { return nil }
        let b = bytes
        let nameLength = Int(b[e.offset + 26]) | Int(b[e.offset + 27]) << 8
        let extra = Int(b[e.offset + 28]) | Int(b[e.offset + 29]) << 8
        let start = e.offset + 30 + nameLength + extra
        guard start + e.compressed <= b.count else { return nil }
        let payload = b[start..<(start + e.compressed)]
        switch e.method {
        case 0:
            return Data(payload)
        case 8:
            if e.size == 0 { return Data() }
            var output = [UInt8](repeating: 0, count: e.size)
            let written = payload.withUnsafeBufferPointer { src in
                compression_decode_buffer(&output, e.size, src.baseAddress!, payload.count, nil, COMPRESSION_ZLIB)
            }
            return written == e.size ? Data(output) : nil
        default:
            return nil
        }
    }
}
