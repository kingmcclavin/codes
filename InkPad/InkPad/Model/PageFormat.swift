import CoreGraphics
import Foundation

enum LengthUnit: String, Codable, CaseIterable, Identifiable {
    case inches, centimeters, millimeters, points, pixels

    var id: String { rawValue }

    /// Page geometry is stored in PostScript points (1/72 in).
    /// Pixels are interpreted as Retina (@2x) pixels, so 1 px = 0.5 pt.
    var pointsPerUnit: CGFloat {
        switch self {
        case .inches: return 72
        case .centimeters: return 72 / 2.54
        case .millimeters: return 72 / 25.4
        case .points: return 1
        case .pixels: return 0.5
        }
    }

    var abbreviation: String {
        switch self {
        case .inches: return "in"
        case .centimeters: return "cm"
        case .millimeters: return "mm"
        case .points: return "pt"
        case .pixels: return "px"
        }
    }

    var displayName: String {
        switch self {
        case .inches: return "Inches"
        case .centimeters: return "Centimeters"
        case .millimeters: return "Millimeters"
        case .points: return "Points"
        case .pixels: return "Pixels"
        }
    }

    func toPoints(_ value: CGFloat) -> CGFloat { value * pointsPerUnit }
    func fromPoints(_ points: CGFloat) -> CGFloat { points / pointsPerUnit }
}

enum PageOrientation: String, Codable, CaseIterable, Identifiable {
    case portrait, landscape
    var id: String { rawValue }
}

/// A page size the user saved for reuse.
struct SavedPageSize: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// Points, as entered (orientation is chosen separately).
    var width: CGFloat
    var height: CGFloat

    var paperSize: PaperSize {
        PaperSize(id: "saved:\(id.uuidString)", name: name, width: width, height: height, category: .saved)
    }
}

struct PaperSize: Identifiable, Hashable {
    enum Category: String { case paper = "Paper", screen = "Screen", other = "Other", saved = "My Sizes" }

    let id: String
    let name: String
    /// Portrait width/height in points.
    let width: CGFloat
    let height: CGFloat
    let category: Category

    func size(for orientation: PageOrientation) -> CGSize {
        let short = min(width, height), long = max(width, height)
        return orientation == .portrait ? CGSize(width: short, height: long) : CGSize(width: long, height: short)
    }

    var subtitle: String {
        switch category {
        case .paper:
            let usesInches = ["letter", "legal", "tabloid"].contains(id)
            let unit: LengthUnit = usesInches ? .inches : .millimeters
            let w = unit.fromPoints(width), h = unit.fromPoints(height)
            let fmt = usesInches ? "%.1f × %.1f in" : "%.0f × %.0f mm"
            return String(format: fmt, w, h)
        case .screen, .other, .saved:
            return String(format: "%.0f × %.0f pt", width, height)
        }
    }

    static let letter = PaperSize(id: "letter", name: "Letter", width: 612, height: 792, category: .paper)
    static let legal = PaperSize(id: "legal", name: "Legal", width: 612, height: 1008, category: .paper)
    static let tabloid = PaperSize(id: "tabloid", name: "Tabloid", width: 792, height: 1224, category: .paper)
    static let a3 = PaperSize(id: "a3", name: "A3", width: 841.89, height: 1190.55, category: .paper)
    static let a4 = PaperSize(id: "a4", name: "A4", width: 595.28, height: 841.89, category: .paper)
    static let a5 = PaperSize(id: "a5", name: "A5", width: 419.53, height: 595.28, category: .paper)
    static let square = PaperSize(id: "square", name: "Square", width: 768, height: 768, category: .other)
    static let ipadPro13 = PaperSize(id: "ipad-13", name: "iPad Pro 12.9″ / 13″", width: 1024, height: 1366, category: .screen)
    static let ipadPro11 = PaperSize(id: "ipad-11", name: "iPad Pro 11″", width: 834, height: 1194, category: .screen)
    static let ipadAir = PaperSize(id: "ipad-air", name: "iPad / iPad Air", width: 820, height: 1180, category: .screen)
    static let ipadMini = PaperSize(id: "ipad-mini", name: "iPad mini", width: 744, height: 1133, category: .screen)
    static let widescreen = PaperSize(id: "16x9", name: "Widescreen 16:9", width: 720, height: 1280, category: .screen)
    static let standard4x3 = PaperSize(id: "4x3", name: "Standard 4:3", width: 768, height: 1024, category: .screen)
    /// Tall scrolling page (fits an 11-inch iPad's width at about 180%).
    static let longScroll = PaperSize(id: "long-455x2500", name: "Long Scroll", width: 455, height: 2500, category: .other)

    static let all: [PaperSize] = [
        .letter, .legal, .tabloid, .a3, .a4, .a5, .square, .longScroll,
        .ipadPro13, .ipadPro11, .ipadAir, .ipadMini, .widescreen, .standard4x3,
    ]

    /// Built-in sizes followed by the user's saved sizes.
    static var allIncludingSaved: [PaperSize] { all + AppPreferences.shared.savedPageSizes.map(\.paperSize) }

    static func find(_ id: String?) -> PaperSize? { allIncludingSaved.first { $0.id == id } }

    /// Finds a preset matching a concrete page size (either orientation).
    static func matching(_ size: CGSize) -> (paper: PaperSize, orientation: PageOrientation)? {
        for p in allIncludingSaved {
            for o in PageOrientation.allCases {
                let s = p.size(for: o)
                if abs(s.width - size.width) < 0.5 && abs(s.height - size.height) < 0.5 { return (p, o) }
            }
        }
        return nil
    }

    static func describe(_ size: CGSize) -> String {
        if let match = matching(size) {
            let p = match.paper
            return p.width == p.height ? p.name : "\(p.name) \(match.orientation == .portrait ? "Portrait" : "Landscape")"
        }
        return String(format: "Custom %.0f × %.0f pt", size.width, size.height)
    }
}

enum PageTemplate: String, Codable, CaseIterable, Identifiable {
    case blank, ruled, grid, dotted, engineering, isometric, cornell, lab

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blank: return "Blank"
        case .ruled: return "Ruled"
        case .grid: return "Grid"
        case .dotted: return "Dotted"
        case .engineering: return "Engineering"
        case .isometric: return "Isometric"
        case .cornell: return "Cornell Notes"
        case .lab: return "Lab Notebook"
        }
    }

    var symbol: String {
        switch self {
        case .blank: return "doc"
        case .ruled: return "line.3.horizontal"
        case .grid: return "grid"
        case .dotted: return "circle.grid.3x3"
        case .engineering: return "square.grid.4x3.fill"
        case .isometric: return "triangle"
        case .cornell: return "rectangle.split.2x1"
        case .lab: return "testtube.2"
        }
    }

    /// Default spacing in points. For engineering paper this is the major
    /// (1 in) spacing, subdivided into 5 minor squares.
    var defaultSpacing: CGFloat {
        switch self {
        case .blank: return 24
        case .ruled: return 24
        case .grid: return 18
        case .dotted: return 18
        case .engineering: return 72
        case .isometric: return 24
        case .cornell: return 24
        case .lab: return 18
        }
    }
}

/// A page of an imported PDF, drawn (as vectors) underneath the ink.
struct PDFPageSource: Codable, Hashable {
    /// PDF file in the document's assets folder.
    var assetName: String
    /// Zero-based page index in that PDF.
    var pageIndex: Int
}

struct PageBackground: Codable, Hashable {
    var color: RGBAColor
    var template: PageTemplate
    var spacing: CGFloat
    /// Imported PDF page shown as the page background, if any.
    var pdf: PDFPageSource?
    /// Page metadata kept with the background so it persists and undoes
    /// with page settings: the title of a section that starts on this page.
    var section: String?
    /// Grows the page downwards while you write near the bottom ("infinite" page).
    var autoExtends: Bool?

    init(color: RGBAColor = .white, template: PageTemplate = .blank, spacing: CGFloat? = nil, pdf: PDFPageSource? = nil) {
        self.color = color
        self.template = template
        self.spacing = spacing ?? template.defaultSpacing
        self.pdf = pdf
    }

    var isDark: Bool { !color.isLight }

    var lineColor: RGBAColor {
        if template == .engineering {
            return isDark ? RGBAColor(r: 0.45, g: 0.75, b: 0.55, a: 0.35) : RGBAColor(r: 0.36, g: 0.62, b: 0.45, a: 0.45)
        }
        return isDark ? RGBAColor(r: 1, g: 1, b: 1, a: 0.18) : RGBAColor(r: 0.45, g: 0.58, b: 0.78, a: 0.45)
    }

    var marginColor: RGBAColor {
        isDark ? RGBAColor(r: 1, g: 0.45, b: 0.45, a: 0.35) : RGBAColor(r: 0.9, g: 0.35, b: 0.35, a: 0.5)
    }
}
