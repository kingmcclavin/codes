import Foundation

/// Smoothly moving top-down camera. `scale` is world yards per screen point.
struct CameraRig {
    var position = Vec2.zero
    var scale = 0.5
    var rotation = 0.0

    var targetPosition = Vec2.zero
    var targetScale = 0.5
    var targetRotation = 0.0

    var stiffness = 3.5

    /// Direction in world space that appears as "up" on screen.
    var screenUp: Vec2 { Vec2(angle: rotation + Double.pi / 2) }

    mutating func snap() {
        position = targetPosition
        scale = targetScale
        rotation = targetRotation
    }

    mutating func update(_ dt: Double) {
        let k = 1 - exp(-stiffness * dt)
        position = Vec2.lerp(position, targetPosition, k)
        // Interpolate zoom in log space so zooming feels even.
        scale = exp(lerpD(log(max(scale, 1e-4)), log(max(targetScale, 1e-4)), k))
        rotation += angleDelta(from: rotation, to: targetRotation) * k
    }

    /// Sets the targets so every point is visible, keeping space for HUD bars.
    /// - Parameters:
    ///   - viewWidth/viewHeight: view size in points.
    ///   - topInset/bottomInset: points covered by HUD at the top / bottom.
    mutating func frame(points: [Vec2], rotation: Double, viewWidth: Double, viewHeight: Double,
                        topInset: Double, bottomInset: Double, padding: Double, minScale: Double, maxScale: Double = 4) {
        guard !points.isEmpty, viewWidth > 10, viewHeight > 10 else { return }
        // Work in camera space (rotated so "up" is the shot direction).
        let local = points.map { $0.rotated(by: -rotation) }
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for p in local {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        let usableH = max(100, viewHeight - topInset - bottomInset)
        let usableW = max(100, viewWidth - 32)
        let w = maxX - minX + padding * 2
        let h = maxY - minY + padding * 2
        let s = max(w / usableW, h / usableH).clamped(minScale, maxScale)
        // Shift so the content is centred in the area between the HUD bars.
        let shiftPoints = (bottomInset - topInset) / 2
        let centerLocal = Vec2((minX + maxX) / 2, (minY + maxY) / 2 - shiftPoints * s)
        targetPosition = centerLocal.rotated(by: rotation)
        targetScale = s
        targetRotation = rotation
    }
}
