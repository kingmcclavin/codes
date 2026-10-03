import UIKit
import UIKit.UIGestureRecognizerSubclass

@MainActor
protocol PencilInputDelegate: AnyObject {
    func pencilBegan(_ touch: UITouch, event: UIEvent)
    func pencilMoved(_ touch: UITouch, event: UIEvent)
    func pencilEnded(_ touch: UITouch, event: UIEvent)
    func pencilCancelled(_ touch: UITouch)
    func pencilEstimatesUpdated(_ touches: Set<UITouch>)
}

/// Delivers raw Apple Pencil touches to the canvas with zero added latency.
///
/// Only `.pencil` touches are accepted by default, which is what provides
/// palm rejection: a resting hand is a `.direct` touch and can never draw.
/// Touches are forwarded the moment UIKit delivers them (the recognizer's
/// state machine is only used so other gestures know drawing is happening).
final class PencilInputRecognizer: UIGestureRecognizer {
    weak var inputDelegate: PencilInputDelegate?
    private var tracked: UITouch?

    var allowsFingerDrawing = false {
        didSet {
            var types: [NSNumber] = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
            if allowsFingerDrawing { types.append(NSNumber(value: UITouch.TouchType.direct.rawValue)) }
            allowedTouchTypes = types
        }
    }

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        requiresExclusiveTouchType = true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let tracked {
            // A second finger while finger-drawing means the user wants to
            // pan/zoom: abandon the stroke (it hasn't been committed yet).
            if tracked.type == .direct, touches.contains(where: { $0.type == .direct }) {
                inputDelegate?.pencilCancelled(tracked)
                self.tracked = nil
                state = .cancelled
            } else {
                for t in touches { ignore(t, for: event) }
            }
            return
        }
        guard let touch = touches.first else { return }
        for t in touches where t !== touch { ignore(t, for: event) }
        tracked = touch
        inputDelegate?.pencilBegan(touch, event: event)
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        inputDelegate?.pencilMoved(tracked, event: event)
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        inputDelegate?.pencilEnded(tracked, event: event)
        self.tracked = nil
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        inputDelegate?.pencilCancelled(tracked)
        self.tracked = nil
        state = .cancelled
    }

    override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
        inputDelegate?.pencilEstimatesUpdated(touches)
    }

    override func reset() {
        super.reset()
        tracked = nil
    }
}
