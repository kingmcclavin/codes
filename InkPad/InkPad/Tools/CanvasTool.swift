import CoreGraphics
import UIKit

/// One input sample, already converted to page coordinates.
struct InputSample {
    var location: CGPoint
    /// Normalized force 0...1 (≈0.25 for a normal writing pressure).
    var force: CGFloat
    var altitude: CGFloat
    var azimuth: CGFloat
    var timestamp: TimeInterval
    /// Set when UIKit will later refine this sample's force.
    var estimationIndex: NSNumber?
    var isPencil: Bool

    func inkPoint(startTime: TimeInterval) -> InkPoint {
        InkPoint(location: location, force: force, altitude: altitude, azimuth: azimuth, t: timestamp - startTime)
    }
}

/// A batch of input for one touch.
struct ToolInput {
    var pageID: UUID
    /// New (coalesced) samples since the previous event, oldest first.
    var samples: [InputSample]
    /// Predicted future samples – for display only, never stored.
    var predicted: [InputSample]
    /// True when the input comes from a finger via a selection drag.
    var isFinger: Bool = false

    var last: InputSample? { samples.last }
}

/// Services the canvas provides to tools. Tools never talk to UIKit views
/// directly, which keeps them small and lets new tools plug in without
/// touching the canvas engine.
@MainActor
protocol ToolHost: AnyObject {
    var editor: EditorModel { get }
    var document: DocumentModel { get }
    var history: History { get }
    var settings: ToolSettings { get }
    var renderer: PageRenderer { get }
    var selection: SelectionController { get }
    /// Current page → screen scale.
    var zoomScale: CGFloat { get }

    /// Transform from page coordinates to overlay (screen) coordinates.
    func pageToOverlay(_ pageID: UUID) -> CGAffineTransform
    func invalidateOverlay(pageRect: CGRect, pageID: UUID)
    func invalidateOverlayScreenRect(_ rect: CGRect)
    func invalidateOverlay()
    /// Keeps drawing just-committed elements in the overlay until the tiled
    /// page layer has re-rendered them, so ink never flickers.
    func showPending(_ elements: [CanvasElement], pageID: UUID)

    func beginTextEditing(_ element: TextElement, pageID: UUID, isNew: Bool)
    func endTextEditing()
    var isEditingText: Bool { get }
    func selectionDidChange()
    func presentSelectionMenu()
    func presentPasteMenu(at point: CGPoint, pageID: UUID)
}

@MainActor
protocol CanvasTool: AnyObject {
    func began(_ input: ToolInput)
    func moved(_ input: ToolInput)
    func ended(_ input: ToolInput)
    func cancelled()
    /// Refined force values for earlier samples (Apple Pencil reports force late).
    func updateEstimated(_ samples: [InputSample])
    /// Pencil hover (Apple Pencil 2 / Pro on supported iPads).
    func hover(at location: CGPoint?, pageID: UUID?)
    /// Draws transient visuals. `ctx` is in overlay (screen) coordinates.
    func drawOverlay(in ctx: CGContext)
    /// Called when another tool becomes active.
    func deactivate()
}

extension CanvasTool {
    func updateEstimated(_ samples: [InputSample]) {}
    func hover(at location: CGPoint?, pageID: UUID?) {}
    func drawOverlay(in ctx: CGContext) {}
    func deactivate() {}
}
