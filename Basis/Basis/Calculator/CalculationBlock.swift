import UIKit
import CoreGraphics
import Foundation

/// A live calculation placed in a note. It stores everything needed to
/// recompute it (a snapshot of the formula, input expressions and chosen
/// units), so a note keeps working even if the library formula is later
/// edited or deleted. The page shows the cached `TextElement.text`, which is
/// regenerated whenever the block is edited.
struct CalculationBlock: Codable, Hashable {
    static let adHocName = "Calculation"

    /// Snapshot of the formula (or of the typed expression lines).
    var formula: Formula
    /// The library formula this came from, if any.
    var libraryID: UUID?
    /// Input expressions by name ("2", "30°", "g0").
    var inputs: [String: String] = [:]
    /// Unit each input is typed in; empty/missing = the declared unit.
    var inputUnits: [String: String] = [:]
    /// Unit each result is shown in; empty/missing = the declared unit.
    var outputUnits: [String: String] = [:]
    var showsTitle = true
    var showsExpression = true

    init(formula: Formula, libraryID: UUID? = nil, inputs: [String: String] = [:]) {
        self.formula = formula
        self.libraryID = libraryID
        self.inputs = inputs
    }

    /// A block for typed lines such as `2 + 3` or `F = 5*9.81`.
    static func expression(_ text: String) -> CalculationBlock {
        var b = CalculationBlock(formula: Formula(name: adHocName, expression: text))
        b.showsTitle = false
        return b
    }

    var isAdHoc: Bool { libraryID == nil }

    // Tolerant decoding: new fields get defaults, so older notes still open.
    private enum CodingKeys: String, CodingKey {
        case formula, libraryID, inputs, inputUnits, outputUnits, showsTitle, showsExpression
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formula = try c.decode(Formula.self, forKey: .formula)
        libraryID = try c.decodeIfPresent(UUID.self, forKey: .libraryID)
        inputs = try c.decodeIfPresent([String: String].self, forKey: .inputs) ?? [:]
        inputUnits = try c.decodeIfPresent([String: String].self, forKey: .inputUnits) ?? [:]
        outputUnits = try c.decodeIfPresent([String: String].self, forKey: .outputUnits) ?? [:]
        showsTitle = try c.decodeIfPresent(Bool.self, forKey: .showsTitle) ?? true
        showsExpression = try c.decodeIfPresent(Bool.self, forKey: .showsExpression) ?? true
    }

    // MARK: Evaluation

    struct Evaluation {
        var inputNames: [String]
        /// Input values converted to the formula's declared units.
        var values: [String: Double]
        var inputErrors: [String: String]
        var result: FormulaResult
    }

    /// An engine that knows this block's formula (even if it was deleted
    /// from the library) plus the library for dependencies.
    static func engine(for block: CalculationBlock, angleMode: AngleMode, library: [Formula],
                       variables: [CalcVariable]) -> CalculatorEngine {
        CalculatorEngine(angleMode: angleMode, formulas: [block.formula] + library.filter { $0.id != block.formula.id },
                         variables: variables)
    }

    /// Declared unit of an input or output (looking into dependency formulas).
    func declaredUnit(_ name: String, engine: CalculatorEngine) -> String {
        if let v = formula.variable(name) { return v.unit }
        return engine.formulas.first { $0.variable(name) != nil }?.variable(name)?.unit ?? ""
    }

    func evaluate(engine: CalculatorEngine) -> Evaluation {
        let names = (try? engine.parse(formula)) == nil ? [] : engine.inputs(of: formula)
        var values: [String: Double] = [:], errors: [String: String] = [:]
        for name in names {
            let text = (inputs[name] ?? "").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            do {
                var v = try engine.evaluate(expression: text, values: [:])
                if let chosen = inputUnits[name], !chosen.isEmpty {
                    v = try UnitLibrary.convert(v, from: chosen, to: declaredUnit(name, engine: engine))
                }
                values[name] = v
            } catch {
                errors[name] = error.localizedDescription
            }
        }
        return Evaluation(inputNames: names, values: values, inputErrors: errors,
                          result: engine.evaluate(formula, inputs: values))
    }

    /// Unit a result is displayed in, and its value converted to it.
    func display(_ o: FormulaOutput) -> (value: Double?, unit: String) {
        guard let v = o.value else { return (nil, o.unit) }
        if let chosen = outputUnits[o.name], !chosen.isEmpty, let x = try? UnitLibrary.convert(v, from: o.unit, to: chosen) {
            return (x, chosen)
        }
        return (v, o.unit)
    }

    // MARK: Text

    /// The text shown on the page.
    func renderText(engine: CalculatorEngine) -> String {
        let ev = evaluate(engine: engine)
        var out: [String] = []
        if showsTitle, !formula.name.isEmpty { out.append(formula.name) }

        let lines = formula.lines
        let singleBare = lines.count == 1 && formula.outputNames.isEmpty && ev.inputNames.isEmpty
        if singleBare, ev.result.error == nil, let o = ev.result.outputs.first {
            out.append("\(MathText.pretty(lines[0])) = \(valueText(o))")
            return out.joined(separator: "\n")
        }

        if showsExpression { out += lines.map(MathText.pretty) }

        let given = ev.inputNames.map { name -> String in
            let text = (inputs[name] ?? "").trimmingCharacters(in: .whitespaces)
            let unit = (inputUnits[name].flatMap { $0.isEmpty ? nil : $0 }) ?? declaredUnit(name, engine: engine)
            let value = text.isEmpty ? fallbackText(name, engine: engine) : MathText.pretty(text)
            return "\(name) = \(value)\(unit.isEmpty ? "" : " \(unit)")"
        }
        if !given.isEmpty { out.append(given.joined(separator: ",  ")) }

        if let e = ev.result.error {
            out.append("⚠︎ \(e.localizedDescription)")
        } else {
            for o in ev.result.outputs {
                out.append("\(o.name) = \(valueText(o))")
            }
        }
        return out.joined(separator: "\n")
    }

    /// What an empty input falls back to: a calculator variable, then the default.
    private func fallbackText(_ name: String, engine: CalculatorEngine) -> String {
        if let x = try? engine.value(ofVariable: name) { return NumberFormatting.format(x) }
        let d = formula.variable(name)?.defaultValue
            ?? engine.formulas.first { $0.variable(name) != nil }?.variable(name)?.defaultValue ?? ""
        return d.isEmpty ? "?" : MathText.pretty(d)
    }

    private func valueText(_ o: FormulaOutput) -> String {
        let d = display(o)
        guard let v = d.value else {
            if case .missingVariable? = o.error { return "?" }
            return "— (\(o.error?.localizedDescription ?? "error"))"
        }
        return NumberFormatting.format(v) + (d.unit.isEmpty ? "" : " \(d.unit)")
    }
}

// MARK: - Page element

extension TextElement {
    /// Typography for calculation cards.
    static func calculationStyle(color: RGBAColor) -> TextStyle {
        TextStyle(fontFamily: "Menlo", fontSize: 15, color: color)
    }

    /// Padding between the text and the card outline, in page points.
    static let cardPadding = CGSize(width: 12, height: 9)

    /// Builds (or rebuilds) the page element for a calculation. Keeps the
    /// top-left corner, rotation and text style of `existing`.
    static func calculationCard(_ block: CalculationBlock, text: String, existing: TextElement? = nil,
                                at center: CGPoint = .zero, style: TextStyle, maxWidth: CGFloat) -> TextElement {
        let style = existing?.style ?? style
        let longest = text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            TextLayout.attributedString(String(line), style: style).size().width
        }.max() ?? 100
        let width = min(max(ceil(longest) + 4, 120), max(maxWidth, 120))
        let size = TextLayout.measure(text, style: style, width: width)
        var box = BoxGeometry(center: center, size: size)
        if let old = existing?.box {
            // Keep the top-left corner in place.
            let topLeft = old.center - CGPoint(x: old.size.width / 2, y: old.size.height / 2).rotated(by: old.rotation)
            box.rotation = old.rotation
            box.center = topLeft + CGPoint(x: size.width / 2, y: size.height / 2).rotated(by: old.rotation)
        }
        return TextElement(id: existing?.id ?? UUID(), text: text, style: style, box: box, calculation: block)
    }
}
