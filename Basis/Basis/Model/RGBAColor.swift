import CoreGraphics
import SwiftUI
import UIKit

/// Device-independent sRGB color stored in documents.
struct RGBAColor: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(hex: UInt32, alpha: Double = 1) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
        a = alpha
    }

    init(_ uiColor: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if !uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) {
            var w: CGFloat = 0
            uiColor.getWhite(&w, alpha: &a)
            r = w; g = w; b = w
        }
        self.init(r: Double(r.clamped(0, 1)), g: Double(g.clamped(0, 1)), b: Double(b.clamped(0, 1)), a: Double(a))
    }

    init(_ color: Color) { self.init(UIColor(color)) }

    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    func withAlpha(_ alpha: Double) -> RGBAColor { RGBAColor(r: r, g: g, b: b, a: alpha) }

    /// Relative luminance (WCAG).
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    var isLight: Bool { luminance > 0.4 }

    /// Approximate equality used to de-duplicate recent colors.
    func isClose(to o: RGBAColor) -> Bool {
        abs(r - o.r) < 0.01 && abs(g - o.g) < 0.01 && abs(b - o.b) < 0.01 && abs(a - o.a) < 0.01
    }

    static let black = RGBAColor(r: 0.07, g: 0.07, b: 0.08)
    static let white = RGBAColor(r: 1, g: 1, b: 1)
    static let offWhite = RGBAColor(r: 0.984, g: 0.973, b: 0.941)
    static let paperBlack = RGBAColor(r: 0.09, g: 0.09, b: 0.10)
    static let paperDarkGray = RGBAColor(r: 0.20, g: 0.20, b: 0.215)

    /// Ink palette tuned to read well on both light and dark paper.
    static let inkPalette: [RGBAColor] = [
        RGBAColor(hex: 0x111114),   // black
        RGBAColor(hex: 0x1F4FD8),   // blue
        RGBAColor(hex: 0xD62828),   // red
        RGBAColor(hex: 0x1E8A4C),   // green
        RGBAColor(hex: 0xF08C00),   // orange
        RGBAColor(hex: 0x7B3FE4),   // purple
        RGBAColor(hex: 0x6B7280),   // gray
        RGBAColor(hex: 0xFFFFFF),   // white
    ]

    static let highlighterPalette: [RGBAColor] = [
        RGBAColor(hex: 0xFFE14D),   // yellow
        RGBAColor(hex: 0x7CF08A),   // green
        RGBAColor(hex: 0x6EC6FF),   // blue
        RGBAColor(hex: 0xFF8AD8),   // pink
        RGBAColor(hex: 0xFFB347),   // orange
        RGBAColor(hex: 0xC6A4FF),   // violet
    ]
}
