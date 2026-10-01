import SwiftUI
import SpriteKit
import UIKit

// Conversions between the platform-neutral game model and Apple frameworks.

extension Vec2 {
    var cg: CGPoint { CGPoint(x: CGFloat(x), y: CGFloat(y)) }

    init(_ p: CGPoint) {
        self.init(Double(p.x), Double(p.y))
    }
}

extension RGBColor {
    var ui: UIColor {
        UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }

    var color: Color {
        Color(red: r, green: g, blue: b, opacity: a)
    }
}

extension WorldRect {
    var cg: CGRect {
        CGRect(x: CGFloat(minX), y: CGFloat(minY), width: CGFloat(width), height: CGFloat(height))
    }
}
