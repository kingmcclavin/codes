import CoreGraphics
import UIKit

/// Live math, like Math Notes: when you pause after writing a line that ends
/// in "=" (or "= ?"), the line is read and its answer is written next to it.
@MainActor
final class AutoMathController {
    private unowned let host: CanvasViewController
    private var pending: DispatchWorkItem?
    /// Lines already solved or rejected (by their stroke ids), so a line is
    /// only read once.
    private var handled: Set<String> = []
    private var running = false

    nonisolated static let defaultsKey = "autoSolveMath"
    nonisolated static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    init(host: CanvasViewController) { self.host = host }

    /// Called after every pen stroke; waits for a short pause in writing.
    func strokeCommitted(_ stroke: Stroke, pageID: UUID) {
        pending?.cancel()
        guard Self.isEnabled, !stroke.style.isHighlighter else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.check(around: stroke, pageID: pageID) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func cancel() { pending?.cancel() }

    // MARK: Line detection

    /// The handwritten line containing `seed`: strokes that overlap it
    /// vertically and are close horizontally, grown transitively.
    nonisolated static func line(containing seed: Stroke, in strokes: [Stroke]) -> [Stroke] {
        var line = [seed]
        var box = seed.bounds
        var remaining = strokes.filter { $0.id != seed.id && !$0.style.isHighlighter }
        var changed = true
        while changed {
            changed = false
            let height = max(box.height, 16)
            for s in remaining {
                let b = s.bounds
                let overlap = min(b.maxY, box.maxY) - max(b.minY, box.minY)
                let centered = b.midY > box.minY - height * 0.25 && b.midY < box.maxY + height * 0.25
                let gap = max(b.minX - box.maxX, box.minX - b.maxX, 0)
                // Tall strokes (a big drawing) don't belong to a text line.
                guard b.height < height * 2.5, gap < height * 1.8,
                      overlap > min(b.height, box.height) * 0.3 || centered else { continue }
                line.append(s)
                box = box.union(b)
                changed = true
            }
            remaining.removeAll { s in line.contains { $0.id == s.id } }
        }
        return line.sorted { $0.bounds.minX < $1.bounds.minX }
    }

    /// The expression of a recognized line that asks for an answer
    /// ("6 + 8 =", "4+5=?"), or nil if the line doesn't end in "=".
    nonisolated static func question(from candidates: [String]) -> String? {
        for raw in candidates {
            var t = raw.trimmingCharacters(in: .whitespaces)
            if t.hasSuffix("?") { t.removeLast(); t = t.trimmingCharacters(in: .whitespaces) }
            guard t.hasSuffix("="), t.filter({ $0 == "=" }).count == 1 else { continue }
            let expression = MathRecognizer.normalize(String(t.dropLast()))
            // Must contain an operation, so a plain "x =" isn't "solved".
            guard expression.contains(where: { "+-×*/÷^√!%".contains($0) }) || expression.contains("(") else { continue }
            return expression
        }
        return nil
    }

    // MARK: Solving

    private func check(around stroke: Stroke, pageID: UUID) {
        guard !running, Self.isEnabled, let page = host.document.page(pageID),
              page.element(stroke.id) != nil else { return }
        let strokes = page.allElements.compactMap { e -> Stroke? in
            if case let .stroke(s) = e { return s }
            return nil
        }
        let line = Self.line(containing: stroke, in: strokes)
        // The last stroke written should be at the end of the line (the "=" or "?").
        let box = line.reduce(CGRect.null) { $0.union($1.bounds) }
        guard stroke.bounds.maxX >= box.maxX - max(box.height, 16) * 0.8 else { return }
        let key = line.map(\.id.uuidString).sorted().joined()
        guard !handled.contains(key) else { return }

        // Already answered (a result sits right after the line)?
        let answerZone = CGRect(x: box.maxX, y: box.minY, width: max(box.height, 20) * 4, height: box.height)
        if page.elements(in: answerZone).contains(where: { if case .text = $0 { return true }; return false }) {
            handled.insert(key)
            return
        }
        guard let image = MathRecognizer.image(of: line.map(CanvasElement.stroke), renderer: host.renderer) else { return }
        running = true
        let engine = CalculatorStore.shared.engine
        MathRecognizer.recognizeLines(in: image) { result in
            // A single written line: merge the readings Vision split up.
            let lines = (try? result.get()) ?? []
            let candidates = lines.count <= 1 ? (lines.first ?? [])
                : [lines.map { $0.first ?? "" }.joined(separator: " ")]
            var answer: (expression: String, value: Double)?
            if let expression = Self.question(from: candidates),
               let value = try? engine.evaluateLine(expression).value, value.isFinite {
                answer = (expression, value)
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.running = false
                self.handled.insert(key)
                guard let answer else { return }
                self.writeAnswer(answer.value, after: box, color: stroke.style.color, pageID: pageID)
            }
        }
    }

    private func writeAnswer(_ value: Double, after box: CGRect, color: RGBAColor, pageID: UUID) {
        guard let page = host.document.page(pageID) else { return }
        let text = NumberFormatting.format(value)
        let size = min(max(box.height * 0.8, 12), 140)
        var style = TextStyle(fontFamily: "Noteworthy", fontSize: size, color: color)
        style.bold = true
        let measured = TextLayout.attributedString(text, style: style).size()
        let width = ceil(measured.width) + 6
        let height = TextLayout.measure(text, style: style, width: width).height
        // Leave room for a "?" written after the "=".
        let origin = CGPoint(x: box.maxX + box.height * 1.1, y: box.midY - height / 2)
        let element = CanvasElement.text(TextElement(text: text, style: style,
                                                     box: BoxGeometry(rect: CGRect(origin: origin, size: CGSize(width: width, height: height)))))
        host.history.perform(ElementsEdit.add([element], to: page, name: "Solve"))
        host.showPending([element], pageID: pageID)
    }
}
