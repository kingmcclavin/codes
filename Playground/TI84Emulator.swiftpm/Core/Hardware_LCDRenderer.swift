/// Converts `LCDFrame`s into RGBA pixels that look like the TI-84 Plus
/// panel, including the effect of the contrast setting. Platform-independent
/// so the same output feeds Core Graphics, Metal or image files.
public struct LCDRenderer: Sendable {
    public struct RGB: Equatable, Sendable {
        public var r, g, b: Double
        public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

        func mix(_ other: RGB, _ t: Double) -> RGB {
            RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
        }
    }

    /// Unlit liquid crystal (the screen background).
    public var background = RGB(0.78, 0.81, 0.70)
    /// A fully driven pixel.
    public var ink = RGB(0.09, 0.11, 0.12)
    /// Screen colour while the display is switched off.
    public var offColor = RGB(0.74, 0.77, 0.67)

    public init() {}

    /// How dark set / clear pixels appear for a contrast value (0...63).
    /// Low contrast washes pixels out; very high contrast darkens the
    /// background too, as on the real panel.
    public func levels(contrast: UInt8) -> (clear: Double, set: Double) {
        let c = Double(min(contrast, 63)) / 63
        let set = min(1, max(0.08, (c - 0.12) / 0.55))
        let clear = max(0, (c - 0.78) / 0.22) * 0.85
        return (clear, set)
    }

    /// 96×64×4 bytes of RGBA (alpha = 255).
    public func rgba(_ frame: LCDFrame) -> [UInt8] {
        var out = [UInt8](repeating: 255, count: LCDFrame.width * LCDFrame.height * 4)
        guard frame.isDisplayOn else {
            let c = bytes(offColor)
            for i in 0..<(LCDFrame.width * LCDFrame.height) {
                out[i * 4] = c.0; out[i * 4 + 1] = c.1; out[i * 4 + 2] = c.2
            }
            return out
        }
        let (clear, set) = levels(contrast: frame.contrast)
        // Precompute the 256 possible shades.
        var table = [(UInt8, UInt8, UInt8)]()
        table.reserveCapacity(256)
        for v in 0..<256 {
            let darkness = clear + (set - clear) * Double(v) / 255
            table.append(bytes(background.mix(ink, darkness)))
        }
        for (i, value) in frame.pixels.enumerated() {
            let c = table[Int(value)]
            out[i * 4] = c.0; out[i * 4 + 1] = c.1; out[i * 4 + 2] = c.2
        }
        return out
    }

    private func bytes(_ c: RGB) -> (UInt8, UInt8, UInt8) {
        func b(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        return (b(c.r), b(c.g), b(c.b))
    }

    /// Binary PPM (P6) image, scaled up by `scale`. Useful for tests and the CLI.
    public func ppm(_ frame: LCDFrame, scale: Int = 4) -> [UInt8] {
        let pixels = rgba(frame)
        let w = LCDFrame.width * scale, h = LCDFrame.height * scale
        var out = Array("P6\n\(w) \(h)\n255\n".utf8)
        out.reserveCapacity(out.count + w * h * 3)
        for y in 0..<h {
            for x in 0..<w {
                let i = ((y / scale) * LCDFrame.width + x / scale) * 4
                out += [pixels[i], pixels[i + 1], pixels[i + 2]]
            }
        }
        return out
    }
}
