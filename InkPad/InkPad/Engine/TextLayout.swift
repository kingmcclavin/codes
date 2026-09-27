import CoreGraphics
import CoreText
import UIKit

/// CoreText-based text layout. Thread safe, so text renders on tile threads.
enum TextLayout {
    static func font(for style: TextStyle, scale: CGFloat = 1) -> UIFont {
        let size = max(1, style.fontSize * scale)
        var traits: UIFontDescriptor.SymbolicTraits = []
        if style.bold { traits.insert(.traitBold) }
        if style.italic { traits.insert(.traitItalic) }
        let base: UIFontDescriptor
        switch style.fontFamily {
        case TextStyle.systemFamily:
            base = UIFont.systemFont(ofSize: size).fontDescriptor
        case "New York":
            base = UIFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif) ?? UIFont.systemFont(ofSize: size).fontDescriptor
        default:
            base = UIFontDescriptor(fontAttributes: [.family: style.fontFamily])
        }
        let descriptor = base.withSymbolicTraits(traits) ?? base
        return UIFont(descriptor: descriptor, size: size)
    }

    static func paragraphAlignment(_ a: TextAlignmentOption) -> NSTextAlignment {
        switch a {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .justified: return .justified
        }
    }

    static func attributedString(_ text: String, style: TextStyle, scale: CGFloat = 1) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = paragraphAlignment(style.alignment)
        let ctColorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        return NSAttributedString(string: text.isEmpty ? " " : text, attributes: [
            .font: font(for: style, scale: scale),
            .foregroundColor: style.color.uiColor,
            ctColorKey: style.color.cgColor,
            .paragraphStyle: para,
        ])
    }

    /// Height needed to lay out `text` at the given wrapping width.
    static func measure(_ text: String, style: TextStyle, width: CGFloat) -> CGSize {
        let attr = attributedString(text, style: style)
        let setter = CTFramesetterCreateWithAttributedString(attr)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            setter, CFRange(location: 0, length: attr.length), nil,
            CGSize(width: max(width, 1), height: .greatestFiniteMagnitude), nil)
        return CGSize(width: width, height: max(ceil(size.height), ceil(style.fontSize * 1.25)))
    }

    /// Draws the element into a y-down context in page coordinates.
    static func draw(_ element: TextElement, in ctx: CGContext) {
        let box = element.box
        let attr = attributedString(element.text, style: element.style)
        let setter = CTFramesetterCreateWithAttributedString(attr)
        ctx.saveGState()
        ctx.concatenate(box.transform)
        // Flip to CoreText's y-up space about the box center (the box is
        // symmetric around the origin, so the rect maps onto itself).
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        // CoreText fills from the top edge (maxY in y-up space). Extend the
        // frame downwards a little so descenders are never clipped.
        let local = box.localRect
        let overflow = element.style.fontSize
        let frameRect = CGRect(x: local.minX, y: local.minY - overflow, width: local.width, height: local.height + overflow)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: attr.length),
                                             CGPath(rect: frameRect, transform: nil), nil)
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }
}
