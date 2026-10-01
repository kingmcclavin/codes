import Foundation

/// What RoundController needs from a view of the course.
/// Implemented by the 2D SpriteKit scene (GolfGameScene) and the 3D SceneKit view (GolfScene3D).
protocol GolfRenderer: AnyObject {
    /// True when the camera turns to follow the aim (3D). Used to keep the wind arrow correct.
    var cameraFollowsAim: Bool { get }
    func attach(_ controller: RoundController)
    func loadHole(_ hole: GolfHole, theme: CourseTheme)
    func placeBall(at p: Vec2)
    func playIntro(completion: @escaping () -> Void)
    func skipIntro()
    func setAim(from: Vec2, to: Vec2, rotation: Double, isPutt: Bool)
    func setPreview(points: [Vec3], landingIndex: Int?, isPutt: Bool, visibleFraction: Double)
    func hidePreview()
    func setOverview(_ on: Bool)
    func launch(_ shot: ShotLaunch)
}

extension GolfGameScene: GolfRenderer {
    var cameraFollowsAim: Bool { false }

    func attach(_ controller: RoundController) {
        self.controller = controller
    }
}
