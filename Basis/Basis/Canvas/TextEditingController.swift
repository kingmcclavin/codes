import UIKit

/// Hosts a UITextView over the canvas while a text element is edited. The
/// text view lives in screen space (scaled font rather than a scaled view) so
/// editing stays sharp at every zoom level.
@MainActor
final class TextEditingController: NSObject, UITextViewDelegate {
    private unowned let host: CanvasViewController
    let textView = UITextView()
    private(set) var element: TextElement?
    private(set) var pageID: UUID?
    private var original: TextElement?

    var isEditing: Bool { element != nil }

    init(host: CanvasViewController) {
        self.host = host
        super.init()
        textView.delegate = self
        textView.backgroundColor = UIColor.appAccent.withAlphaComponent(0.04)
        textView.layer.borderColor = UIColor.appAccent.withAlphaComponent(0.6).cgColor
        textView.layer.borderWidth = 1
        textView.isScrollEnabled = false
        textView.clipsToBounds = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.autocorrectionType = .default
        textView.smartDashesType = .no
    }

    func begin(_ e: TextElement, pageID: UUID, isNew: Bool, in parent: UIView) {
        if isEditing { end() }
        element = e
        self.pageID = pageID
        original = isNew ? nil : e
        if !isNew { host.document.setHidden([e.id], page: pageID) }
        textView.text = e.text
        parent.addSubview(textView)
        layout()
        textView.becomeFirstResponder()
    }

    /// Re-positions the text view after scrolling or zooming.
    func layout() {
        guard let element, let pageID else { return }
        let t = host.pageToOverlay(pageID)
        let z = t.a
        textView.transform = .identity
        textView.bounds = CGRect(x: 0, y: 0, width: element.box.size.width * z, height: element.box.size.height * z)
        textView.center = element.box.center.applying(t)
        textView.transform = CGAffineTransform(rotationAngle: element.box.rotation)
        applyStyle(element.style, zoom: z)
    }

    private func applyStyle(_ style: TextStyle, zoom: CGFloat) {
        let font = TextLayout.font(for: style, scale: zoom)
        let para = NSMutableParagraphStyle()
        para.alignment = TextLayout.paragraphAlignment(style.alignment)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: style.color.uiColor, .paragraphStyle: para]
        let selected = textView.selectedRange
        textView.attributedText = NSAttributedString(string: textView.text ?? "", attributes: attrs)
        textView.typingAttributes = attrs
        textView.selectedRange = selected
        textView.tintColor = style.color.isLight ? .appAccent : style.color.uiColor
    }

    func updateStyle(_ style: TextStyle) {
        guard var e = element else { return }
        e.style = style
        element = e
        remeasure()
    }

    func textViewDidChange(_ textView: UITextView) {
        guard var e = element else { return }
        e.text = textView.text ?? ""
        element = e
        remeasure()
    }

    private func remeasure() {
        guard var e = element else { return }
        let size = TextLayout.measure(e.text, style: e.style, width: e.box.size.width)
        let dh = size.height - e.box.size.height
        if abs(dh) > 0.01 {
            // Grow downwards: keep the top edge fixed.
            e.box.center = e.box.center + CGPoint(x: 0, y: dh / 2).rotated(by: e.box.rotation)
            e.box.size.height = size.height
            element = e
        }
        let selected = textView.selectedRange
        layout()
        textView.selectedRange = selected
    }

    /// Commits the edit as one undoable action.
    func end() {
        guard let e = element, let pageID, let page = host.document.page(pageID) else { reset(); return }
        textView.delegate = nil
        textView.resignFirstResponder()
        textView.delegate = self
        textView.removeFromSuperview()
        host.document.setHidden([], page: pageID)

        let empty = e.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if let original {
            if empty {
                host.history.perform(ElementsEdit.remove([original.id], from: page, name: "Delete Text"))
            } else if original.text != e.text || original.style != e.style || original.box != e.box {
                host.history.perform(ElementsEdit.update([(.text(original), .text(e))], page: page, name: "Edit Text"))
                host.showPending([.text(e)], pageID: pageID)
            }
        } else if !empty {
            host.history.perform(ElementsEdit.add([.text(e)], to: page, name: "Add Text"))
            host.showPending([.text(e)], pageID: pageID)
        }
        reset()
    }

    private func reset() {
        element = nil
        pageID = nil
        original = nil
        host.editor.isEditingText = false
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        // Keyboard dismissed by the user (e.g. hardware key) – commit.
        if isEditing { end() }
    }
}
