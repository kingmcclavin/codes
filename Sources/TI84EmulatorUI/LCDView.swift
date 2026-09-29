#if canImport(SwiftUI) && canImport(UIKit)
import CoreGraphics
import SwiftUI
import TI84EmulatorCore

/// Draws the emulated 96×64 LCD from its pixel buffer.
///
/// Each frame becomes one small `CGImage` scaled up with nearest-neighbour
/// filtering, so the whole screen is a single view that only redraws when
/// the emulator publishes a changed frame.
struct LCDView: View {
    let frame: LCDFrame
    var renderer = LCDRenderer()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = Self.makeImage(frame, renderer: renderer) {
                    Image(decorative: image, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(CGFloat(LCDFrame.width) / CGFloat(LCDFrame.height), contentMode: .fit)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(CGFloat(LCDFrame.width) / CGFloat(LCDFrame.height), contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Calculator screen")
    }

    static func makeImage(_ frame: LCDFrame, renderer: LCDRenderer) -> CGImage? {
        let rgba = renderer.rgba(frame)
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: LCDFrame.width, height: LCDFrame.height,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: LCDFrame.width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}

/// The dark bezel and glass around the LCD.
struct LCDBezel: View {
    let frame: LCDFrame

    var body: some View {
        LCDView(frame: frame)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: 0.74, green: 0.77, blue: 0.67))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.black.opacity(0.35), lineWidth: 1)
            )
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color(white: 0.20), Color(white: 0.10)],
                                         startPoint: .top, endPoint: .bottom))
            )
    }
}
#endif
