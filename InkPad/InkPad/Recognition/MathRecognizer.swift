import CoreGraphics
import UIKit
import Vision

/// Reads handwritten math (selected ink) into calculator expressions, using
/// Apple's on-device Vision text recognition. Works offline.
enum MathRecognizer {
    enum RecognitionError: LocalizedError {
        case nothingToRead, notRecognized
        var errorDescription: String? {
            switch self {
            case .nothingToRead: return "Select some handwriting first."
            case .notRecognized: return "Couldn't read that handwriting. Try writing a little larger and more spaced out."
            }
        }
    }

    /// Ink rendered black on white, scaled to a size Vision reads well.
    static func image(of elements: [CanvasElement], renderer: PageRenderer) -> CGImage? {
        let ink = elements.filter {
            if case let .stroke(s) = $0 { return !s.style.isHighlighter }
            if case .shape = $0 { return true }
            return false
        }
        guard !ink.isEmpty else { return nil }
        let bounds = ink.reduce(CGRect.null) { $0.union($1.bounds) }
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let scale = min(4, max(0.5, 1400 / max(bounds.width, bounds.height)))
        let pad: CGFloat = 40
        let size = CGSize(width: ceil(bounds.width * scale + 2 * pad), height: ceil(bounds.height * scale + 2 * pad))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            cg.translateBy(x: pad, y: pad)
            cg.scaleBy(x: scale, y: scale)
            cg.translateBy(x: -bounds.minX, y: -bounds.minY)
            for e in ink {
                renderer.draw(e.recolored(.black), stamp: nil, in: cg, background: PageBackground())
            }
        }
        return image.cgImage
    }

    /// Recognized lines (top to bottom), each with a few alternative readings.
    static func recognizeLines(in image: CGImage, completion: @escaping (Result<[[String]], Error>) -> Void) {
        let request = VNRecognizeTextRequest { request, error in
            if let error { completion(.failure(error)); return }
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            let lines = observations
                .sorted { $0.boundingBox.midY > $1.boundingBox.midY }   // Vision's y axis points up
                .map { $0.topCandidates(5).map(\.string) }
                .filter { !$0.isEmpty }
            completion(lines.isEmpty ? .failure(RecognitionError.notRecognized) : .success(lines))
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.customWords = ["sin", "cos", "tan", "sqrt", "log", "ln", "pi", "asin", "acos", "atan", "exp", "abs"]
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Picks, for every line, the first reading the calculator understands.
    static func expression(from lines: [[String]], engine: CalculatorEngine) -> String? {
        let parser = { (s: String) -> Bool in
            (try? ExpressionParser(knownNames: engine.knownNames).parseStatement(s)) != nil
        }
        let chosen = lines.compactMap { candidates -> String? in
            let normalized = candidates.map(normalize).filter { !$0.isEmpty }
            return normalized.first(where: parser) ?? normalized.first
        }
        let text = chosen.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    /// Cleans up typical misreadings of handwritten math:
    /// `2 x 3` → `2×3`, `1O` → `10`, `—` → `-`, a trailing `=` or `= ?` is dropped,
    /// and for `2+3=5` only the left side is kept.
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacements: [(String, String)] = [
            ("—", "-"), ("–", "-"), ("−", "-"), ("÷", "/"), (":", "/"), ("**", "^"),
            ("·", "*"), ("•", "*"), ("‘", ""), ("’", ""), ("\"", ""),
        ]
        for (a, b) in replacements { s = s.replacingOccurrences(of: a, with: b) }

        // Equals: "expr =" or "expr = ?" → expr; "a + b = c" → "a + b",
        // but keep assignments like "m = 5".
        if let eq = s.firstIndex(of: "=") {
            let lhs = String(s[..<eq]).trimmingCharacters(in: .whitespaces)
            let rhs = String(s[s.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            let lhsIsName = !lhs.isEmpty && lhs.allSatisfy { $0.isLetter || $0 == "_" } && lhs.count <= 3
            if rhs.isEmpty || rhs == "?" || !lhsIsName { s = lhs }
        }

        let chars = Array(s)
        var out = ""
        func isDigit(_ i: Int) -> Bool { i >= 0 && i < chars.count && chars[i].isNumber }
        func neighbourDigit(_ i: Int) -> Bool {
            // Nearest non-space neighbours on both sides.
            var l = i - 1; while l >= 0, chars[l] == " " { l -= 1 }
            var r = i + 1; while r < chars.count, chars[r] == " " { r += 1 }
            return isDigit(l) && isDigit(r)
        }
        func touchesDigit(_ i: Int) -> Bool { isDigit(i - 1) || isDigit(i + 1) }
        for (i, c) in chars.enumerated() {
            if c == "×" || ((c == "x" || c == "X") && neighbourDigit(i)) {
                out.append("×")
            } else if (c == "O" || c == "o"), touchesDigit(i), !(i + 1 < chars.count && chars[i + 1].isLetter),
                      !(i > 0 && chars[i - 1].isLetter) {
                out.append("0")
            } else if (c == "l" || c == "I" || c == "|"), touchesDigit(i) {
                out.append("1")
            } else {
                out.append(c)
            }
        }
        // Collapse runs of spaces.
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        out = out.trimmingCharacters(in: .whitespaces)
        return out
    }
}
