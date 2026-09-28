import UIKit

/// "Pull to Add Page" indicator shown when the user drags past the end of
/// the document: a ring fills as they pull; once full it turns into a solid
/// button ("Release to Add Page") and releasing appends a page.
final class PullToAddPageView: UIView {
    /// Pull distance (screen points) needed to add a page.
    static let threshold: CGFloat = 140

    private let ringSize: CGFloat = 60
    private let track = CAShapeLayer()
    private let progressRing = CAShapeLayer()
    private let fill = CAShapeLayer()
    private let icon = UIImageView()
    private let arrow = UIImageView()
    private let label = UILabel()
    private let ghostPage = UIView()
    private(set) var isArmed = false
    private let feedback = UIImpactFeedbackGenerator(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        alpha = 0

        ghostPage.layer.cornerRadius = 2
        ghostPage.layer.borderWidth = 1
        addSubview(ghostPage)

        let circle = UIBezierPath(arcCenter: CGPoint(x: ringSize / 2, y: ringSize / 2), radius: ringSize / 2 - 2,
                                  startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: true).cgPath
        for l in [fill, track, progressRing] {
            l.path = circle
            l.frame = CGRect(x: 0, y: 0, width: ringSize, height: ringSize)
            layer.addSublayer(l)
        }
        track.fillColor = UIColor.clear.cgColor
        track.lineWidth = 3
        progressRing.fillColor = UIColor.clear.cgColor
        progressRing.strokeColor = UIColor.systemBlue.cgColor
        progressRing.lineWidth = 3
        progressRing.lineCap = .round
        progressRing.strokeEnd = 0
        fill.fillColor = UIColor.systemBlue.cgColor
        fill.opacity = 0

        icon.image = UIImage(systemName: "doc.badge.plus")
        icon.contentMode = .scaleAspectFit
        addSubview(icon)

        arrow.image = UIImage(systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
        arrow.tintColor = .systemBlue
        arrow.contentMode = .scaleAspectFit
        addSubview(arrow)

        label.font = .preferredFont(forTextStyle: .footnote)
        label.textAlignment = .center
        addSubview(label)
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        updateColors()
    }

    private func updateColors() {
        track.strokeColor = UIColor.secondaryLabel.withAlphaComponent(0.35).cgColor
        ghostPage.backgroundColor = UIColor.label.withAlphaComponent(0.04)
        ghostPage.layer.borderColor = UIColor.label.withAlphaComponent(0.08).cgColor
        label.textColor = isArmed ? .systemBlue : .secondaryLabel
        icon.tintColor = isArmed ? .white : .secondaryLabel
    }

    /// - Parameters:
    ///   - pull: how far past the end of the content the user has dragged (screen points)
    ///   - pageBottom: y (in this view's superview) of the last page's bottom edge
    ///   - pageFrame: last page frame in screen coordinates (for the ghost page)
    func update(pull: CGFloat, pageBottom: CGFloat, pageFrame: CGRect) {
        guard pull > 1 else {
            alpha = 0
            setArmed(false)
            return
        }
        let progress = min(pull / Self.threshold, 1)
        alpha = min(1, pull / 40)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressRing.strokeEnd = progress
        CATransaction.commit()
        setArmed(pull >= Self.threshold)

        // Lay out inside the revealed strip below the last page.
        let bottom = superview?.bounds.maxY ?? bounds.maxY
        let revealTop = min(pageBottom, bottom - pull)
        let midY = revealTop + (bottom - revealTop) * 0.42
        let cx = pageFrame.midX

        let ringFrame = CGRect(x: cx - ringSize / 2, y: midY - ringSize / 2, width: ringSize, height: ringSize)
        for l in [fill, track, progressRing] { l.frame = ringFrame }
        icon.frame = ringFrame.insetBy(dx: 18, dy: 18)
        arrow.frame = CGRect(x: cx - 11, y: ringFrame.minY - 30, width: 22, height: 22)
        arrow.alpha = isArmed ? 0 : 1
        label.text = isArmed ? "Release to Add Page" : "Pull to Add Page"
        label.frame = CGRect(x: cx - 120, y: ringFrame.maxY + 6, width: 240, height: 20)

        // A faint outline of the page-to-be peeks in from the bottom.
        let ghostTop = max(label.frame.maxY + 16, bottom - pull * 0.45)
        ghostPage.frame = CGRect(x: pageFrame.minX, y: ghostTop, width: pageFrame.width, height: max(pageFrame.height, 200))
    }

    private func setArmed(_ armed: Bool) {
        guard armed != isArmed else { return }
        isArmed = armed
        if armed { feedback.impactOccurred() } else { feedback.prepare() }
        UIView.animate(withDuration: 0.15) {
            self.fill.opacity = armed ? 1 : 0
            self.progressRing.opacity = armed ? 0 : 1
            self.track.opacity = armed ? 0 : 1
            self.icon.transform = armed ? CGAffineTransform(scaleX: 1.15, y: 1.15) : .identity
        }
        updateColors()
    }
}
