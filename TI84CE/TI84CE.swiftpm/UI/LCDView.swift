import SwiftUI
import UIKit

/// Shows the emulated 320x240 LCD. The pixel buffer produced by the emulated panel
/// is wrapped in a CGImage and handed to a Core Animation layer (GPU composited,
/// nearest-neighbour scaled). A display link polls for new frames; nothing is
/// redrawn unless the calculator's screen actually changed.
struct LCDView: UIViewRepresentable {
    let runner: EmulatorRunner
    var pixelGrid: Bool

    func makeUIView(context: Context) -> LCDDisplayView {
        let v = LCDDisplayView()
        v.runner = runner
        v.pixelGrid = pixelGrid
        return v
    }

    func updateUIView(_ view: LCDDisplayView, context: Context) {
        view.runner = runner
        view.pixelGrid = pixelGrid
    }
}

final class LCDDisplayView: UIView {
    var runner: EmulatorRunner? {
        didSet { if runner !== oldValue { serial = .max } }
    }
    var pixelGrid = false {
        didSet { gridLayer.isHidden = !pixelGrid; setNeedsLayout() }
    }

    private var link: CADisplayLink?
    private var serial: UInt64 = .max
    private let imageLayer = CALayer()
    private let dimLayer = CALayer()
    private let gridLayer = CALayer()
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
        imageLayer.magnificationFilter = .nearest
        imageLayer.minificationFilter = .trilinear
        imageLayer.contentsGravity = .resize
        layer.addSublayer(imageLayer)
        dimLayer.backgroundColor = UIColor.black.cgColor
        dimLayer.opacity = 0
        layer.addSublayer(dimLayer)
        gridLayer.isHidden = true
        gridLayer.contentsGravity = .resize
        gridLayer.magnificationFilter = .nearest
        gridLayer.contents = LCDDisplayView.gridImage()
        gridLayer.opacity = 0.18
        layer.addSublayer(gridLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        dimLayer.frame = bounds
        gridLayer.frame = bounds
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.preferredFramesPerSecond = 60
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick() {
        guard let runner, let (frame, brightness) = runner.latestFrame(newerThan: serial) else { return }
        serial = frame.serial
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = makeImage(frame)
        dimLayer.opacity = Float(max(0, min(0.85, 1 - brightness)))
        CATransaction.commit()
    }

    private func makeImage(_ frame: LCDFrame) -> CGImage? {
        let data = Data(frame.pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: frame.width, height: frame.height,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: frame.width * 4,
                       space: colorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// A faint grid that outlines each LCD pixel (optional, like the real screen).
    private static func gridImage() -> CGImage? {
        let scale = 4
        let w = LCDFrame.width * scale, h = LCDFrame.height * scale
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(UIColor.black.cgColor)
        for x in stride(from: 0, to: w, by: scale) { ctx.fill(CGRect(x: x, y: 0, width: 1, height: h)) }
        for y in stride(from: 0, to: h, by: scale) { ctx.fill(CGRect(x: 0, y: y, width: w, height: 1)) }
        return ctx.makeImage()
    }
}
