import CoreGraphics
import Foundation

/// Serialized form of a page.
struct PageData: Codable, Identifiable {
    var id: UUID = UUID()
    var size: CGSize
    var background: PageBackground
    var elements: [CanvasElement] = []
}

/// Where the user left off.
struct ViewState: Codable, Equatable {
    var pageIndex: Int = 0
    /// 0 means "not yet set" – the canvas fits the page width on first open.
    var zoomScale: CGFloat = 0
    /// Content offset in unzoomed canvas coordinates.
    var contentOffset: CGPoint = .zero
}

/// Small file describing a document; the library only reads this.
struct DocumentManifest: Codable {
    static let currentFormatVersion = 1

    var formatVersion = DocumentManifest.currentFormatVersion
    var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var pageIDs: [UUID]
    /// Size of the first page, for display in the library.
    var firstPageSize: CGSize
    var toolSettings: ToolSettings
    var viewState: ViewState
    /// Library folder containing the document (nil = top level).
    var folderID: UUID?
    /// Custom library color and SF Symbol (nil = default).
    var color: RGBAColor?
    var icon: String?
}

enum ToolKind: String, Codable, CaseIterable, Identifiable {
    case pen, highlighter, eraser, shapes, lasso, text

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .eraser: return "Eraser"
        case .shapes: return "Shapes"
        case .lasso: return "Lasso"
        case .text: return "Text"
        }
    }

    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        case .shapes: return "square.on.circle"
        case .lasso: return "lasso"
        case .text: return "textformat"
        }
    }
}

enum EraserMode: String, Codable, CaseIterable, Identifiable {
    /// Removes whole strokes/objects that the eraser touches.
    case object
    /// Removes only the touched portion of ink ("pixel" eraser, still vector based).
    case partial
    var id: String { rawValue }
    var displayName: String { self == .object ? "Stroke" : "Pixel" }
}

enum ScribbleEraseMode: String, Codable, CaseIterable, Identifiable {
    /// Individual strokes crossed by the scribble.
    case strokes
    /// Whole objects (clusters of touching strokes, e.g. a word) under the scribble.
    case objects
    /// Everything inside the scribbled region, partially erasing strokes at the edge.
    case region
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .strokes: return "Strokes"
        case .objects: return "Whole Objects"
        case .region: return "Scribbled Region"
        }
    }
}

struct EraserSettings: Codable, Equatable {
    var mode: EraserMode = .object
    /// Diameter in screen points (the eraser feels the same at every zoom).
    var size: CGFloat = 24
    var erasesHighlighterOnly = false
}

struct PenPreset: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var style: StrokeStyle
    var isBuiltIn: Bool

    static let fine = PenPreset(id: UUID(uuidString: "6F1C2E54-0000-4000-8000-000000000001")!, name: "Fine Pen",
                                style: StrokeStyle(kind: .fineliner, color: RGBAColor.inkPalette[0], width: 1.0, pressureSensitivity: 0.15),
                                isBuiltIn: true)
    static let ballpoint = PenPreset(id: UUID(uuidString: "6F1C2E54-0000-4000-8000-000000000002")!, name: "Ballpoint",
                                     style: StrokeStyle(kind: .ballpoint, color: RGBAColor.inkPalette[0], width: 1.8, pressureSensitivity: 0.55),
                                     isBuiltIn: true)
    static let fountain = PenPreset(id: UUID(uuidString: "6F1C2E54-0000-4000-8000-000000000003")!, name: "Fountain",
                                    style: StrokeStyle(kind: .fountain, color: RGBAColor.inkPalette[1], width: 2.2, pressureSensitivity: 0.95),
                                    isBuiltIn: true)
    static let marker = PenPreset(id: UUID(uuidString: "6F1C2E54-0000-4000-8000-000000000004")!, name: "Marker",
                                  style: StrokeStyle(kind: .marker, color: RGBAColor.inkPalette[2], width: 5, opacity: 0.95, pressureSensitivity: 0.1),
                                  isBuiltIn: true)
    static let pencil = PenPreset(id: UUID(uuidString: "6F1C2E54-0000-4000-8000-000000000005")!, name: "Pencil",
                                  style: StrokeStyle(kind: .pencil, color: RGBAColor(hex: 0x3A3A3F), width: 1.4, opacity: 0.8,
                                                     pressureSensitivity: 0.6, tiltSensitivity: 0.6),
                                  isBuiltIn: true)
    static let highlighter = PenPreset(id: UUID(uuidString: "6F1C2E54-0000-4000-8000-000000000006")!, name: "Highlighter",
                                       style: StrokeStyle(kind: .highlighter, color: RGBAColor.highlighterPalette[0], width: 16, opacity: 0.4,
                                                          pressureSensitivity: 0),
                                       isBuiltIn: true)

    static let builtInPens: [PenPreset] = [.fine, .ballpoint, .fountain, .marker, .pencil]
    static let builtInHighlighters: [PenPreset] = [.highlighter]
}

/// Tool configuration stored with each document so it reopens exactly as left.
struct ToolSettings: Codable, Equatable {
    var currentTool: ToolKind = .pen
    var pen: StrokeStyle = PenPreset.ballpoint.style
    var highlighter: StrokeStyle = PenPreset.highlighter.style
    var shape = ShapeStyle()
    var eraser = EraserSettings()
    var text = TextStyle()
    var scribbleToErase = true
    var scribbleMode: ScribbleEraseMode = .strokes
    /// Hold the pencil still at the end of a stroke to snap it to a shape.
    var holdToSnapShapes = true
    var holdDuration: Double = 0.5
    /// Allow drawing with a finger (then two fingers pan).
    var fingerDrawing = false

    init() {}

    // Tolerant decoding so documents survive future additions to the settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ToolSettings()
        currentTool = (try? c.decode(ToolKind.self, forKey: .currentTool)) ?? d.currentTool
        pen = (try? c.decode(StrokeStyle.self, forKey: .pen)) ?? d.pen
        highlighter = (try? c.decode(StrokeStyle.self, forKey: .highlighter)) ?? d.highlighter
        shape = (try? c.decode(ShapeStyle.self, forKey: .shape)) ?? d.shape
        eraser = (try? c.decode(EraserSettings.self, forKey: .eraser)) ?? d.eraser
        text = (try? c.decode(TextStyle.self, forKey: .text)) ?? d.text
        scribbleToErase = (try? c.decode(Bool.self, forKey: .scribbleToErase)) ?? d.scribbleToErase
        scribbleMode = (try? c.decode(ScribbleEraseMode.self, forKey: .scribbleMode)) ?? d.scribbleMode
        holdToSnapShapes = (try? c.decode(Bool.self, forKey: .holdToSnapShapes)) ?? d.holdToSnapShapes
        holdDuration = (try? c.decode(Double.self, forKey: .holdDuration)) ?? d.holdDuration
        fingerDrawing = (try? c.decode(Bool.self, forKey: .fingerDrawing)) ?? d.fingerDrawing
    }
}
