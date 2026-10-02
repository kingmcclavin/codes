import SwiftUI
import UIKit

/// The friendly calculator: a big display and a simple keypad, with the
/// scientific keys tucked behind a toggle. Used full screen and in the
/// floating calculator over notebooks.
struct CalculatorPad: View {
    /// Smaller keys for the floating calculator.
    var compact = false
    /// Shows an "Insert on Page" button; receives the expression to insert.
    var onInsert: ((String) -> Void)?

    @EnvironmentObject private var calc: CalculatorStore
    @AppStorage("calcScientificFull") private var scientificFull = false
    @AppStorage("calcScientificFloating") private var scientificFloating = false
    @State private var result: (expression: String, value: Double)?
    @State private var error: String?
    @State private var showFunctions = false
    @State private var showConstants = false
    @FocusState private var focused: Bool

    private var scientific: Bool {
        get { compact ? scientificFloating : scientificFull }
        nonmutating set { if compact { scientificFloating = newValue } else { scientificFull = newValue } }
    }

    private var spacing: CGFloat { compact ? 6 : 10 }

    var body: some View {
        VStack(spacing: spacing) {
            display
            if scientific { scientificKeys }
            basicKeys
            if let onInsert {
                Button {
                    if let e = insertableExpression { onInsert(e) }
                } label: {
                    Label("Insert on Page", systemImage: "square.and.arrow.down.on.square")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.bordered)
                .disabled(insertableExpression == nil)
            }
        }
        .focusable(!compact)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(action: handleKey)
        .onAppear { if !compact { focused = true } }
    }

    // MARK: Display

    private var preview: String? {
        let t = calc.draftExpression.trimmingCharacters(in: .whitespaces)
        guard result == nil, !t.isEmpty, let r = try? calc.engine.evaluateLine(t) else { return nil }
        return "= " + NumberFormatting.format(r.value)
    }

    private var display: some View {
        VStack(alignment: .trailing, spacing: compact ? 2 : 6) {
            HStack(spacing: 8) {
                Button {
                    calc.angleMode = calc.angleMode == .degrees ? .radians : .degrees
                } label: {
                    Text(calc.angleMode == .degrees ? "DEG" : "RAD")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Angle unit")
                Button {
                    withAnimation(.snappy) { scientific.toggle() }
                } label: {
                    Text(scientific ? "Basic" : "Scientific")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(1)
                } else if let result {
                    Text(MathText.pretty(result.expression) + " =")
                        .font(.system(compact ? .caption : .callout, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let preview {
                    Text(preview)
                        .font(.system(compact ? .caption : .callout, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
            }
            Text(mainText)
                .font(.system(size: compact ? 30 : 48, weight: .light, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .textSelection(.enabled)
                .contentTransition(.numericText())
        }
        .padding(compact ? 10 : 16)
        .background(RoundedRectangle(cornerRadius: compact ? 14 : 20, style: .continuous)
            .fill(Color(uiColor: .secondarySystemBackground)))
        .contentShape(Rectangle())
        .onTapGesture { if !compact { focused = true } }
    }

    private var mainText: String {
        if let result { return NumberFormatting.format(result.value) }
        return calc.draftExpression.isEmpty ? "0" : MathText.pretty(calc.draftExpression)
    }

    // MARK: Keys

    private enum Kind { case digit, op, function, clear, equals }

    private struct Key: Identifiable {
        let title: String
        let kind: Kind
        let action: () -> Void
        var id: String { title }
    }

    private var basicKeys: some View {
        let rows: [[Key]] = [
            [Key(title: "AC", kind: .clear, action: clear), Key(title: "(", kind: .function) { type("(") },
             Key(title: ")", kind: .function) { type(")") }, Key(title: "÷", kind: .op) { type("÷") }],
            [digit("7"), digit("8"), digit("9"), Key(title: "×", kind: .op) { type("×") }],
            [digit("4"), digit("5"), digit("6"), Key(title: "−", kind: .op) { type("-") }],
            [digit("1"), digit("2"), digit("3"), Key(title: "+", kind: .op) { type("+") }],
            [digit("0"), Key(title: ".", kind: .digit) { type(".") }, Key(title: "⌫", kind: .function, action: backspace),
             Key(title: "=", kind: .equals, action: evaluate)],
        ]
        return keyGrid(rows, height: compact ? 42 : 64, font: compact ? .title3 : .title)
    }

    private var scientificKeys: some View {
        let rows: [[Key]] = [
            [fn("sin", "sin("), fn("cos", "cos("), fn("tan", "tan("), fn("√", "√("), fn("x²", "²"), fn("xʸ", "^")],
            [fn("sin⁻¹", "asin("), fn("cos⁻¹", "acos("), fn("tan⁻¹", "atan("), fn("log", "log("), fn("ln", "ln("), fn("eˣ", "exp(")],
            [fn("π", "π"), fn("e", "e"), fn("°", "°"), fn("n!", "!"), fn("ans", "ans"),
             Key(title: "more", kind: .function) { showFunctions = true }],
        ]
        return keyGrid(rows, height: compact ? 32 : 44, font: compact ? .footnote : .callout)
            .popover(isPresented: $showFunctions) {
                VStack(spacing: 0) {
                    Button("Constants (g₀, c, h, k …)", systemImage: "atom") { showFunctions = false; showConstants = true }
                        .padding(10)
                    Divider()
                    FunctionPicker { type($0); showFunctions = false }
                }
            }
            .popover(isPresented: $showConstants) {
                ConstantsPicker { type($0); showConstants = false }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func digit(_ d: String) -> Key { Key(title: d, kind: .digit) { type(d) } }
    private func fn(_ title: String, _ text: String) -> Key { Key(title: title, kind: .function) { type(text) } }

    private func keyGrid(_ rows: [[Key]], height: CGFloat, font: Font) -> some View {
        Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
            ForEach(rows.indices, id: \.self) { r in
                GridRow {
                    ForEach(rows[r]) { key in
                        PadKey(title: key.title, kind: key.kind, height: height, font: font, action: key.action)
                    }
                }
            }
        }
    }

    private struct PadKey: View {
        let title: String
        let kind: Kind
        let height: CGFloat
        let font: Font
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(font.weight(kind == .digit ? .regular : .medium))
                    .fontDesign(.rounded)
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background(RoundedRectangle(cornerRadius: height * 0.32, style: .continuous).fill(background))
                    .foregroundStyle(foreground)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableKeyStyle())
            .accessibilityLabel(title)
        }

        private var background: Color {
            switch kind {
            case .digit: return Color(uiColor: .secondarySystemBackground)
            case .op: return Color.accentColor.opacity(0.15)
            case .function: return Color(uiColor: .tertiarySystemFill)
            case .clear: return Color.orange.opacity(0.16)
            case .equals: return Color.accentColor
            }
        }

        private var foreground: Color {
            switch kind {
            case .op: return .accentColor
            case .clear: return .orange
            case .equals: return .white
            default: return .primary
            }
        }
    }

    // MARK: Input

    private static let continuing: Set<String> = ["+", "-", "×", "÷", "^", "²", "!", "%", "°"]

    /// After a result, an operator continues from it; anything else starts over.
    private func type(_ s: String) {
        error = nil
        if let r = result {
            calc.draftExpression = Self.continuing.contains(s) ? NumberFormatting.plain(r.value) + s : s
            result = nil
        } else {
            calc.draftExpression += s
        }
    }

    private func clear() {
        calc.draftExpression = ""
        result = nil
        error = nil
    }

    private func backspace() {
        if result != nil { clear(); return }
        if !calc.draftExpression.isEmpty { calc.draftExpression.removeLast() }
        error = nil
    }

    private func evaluate() {
        let t = calc.draftExpression.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, result == nil else { return }
        do {
            let r = try calc.evaluate(t)
            withAnimation(.snappy) { result = (t, r.value) }
            calc.draftExpression = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// What "Insert on Page" places: the last answer's expression, or what's typed.
    private var insertableExpression: String? {
        if let r = result { return r.expression }
        let t = calc.draftExpression.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    /// Hardware keyboard support.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .return { evaluate(); return .handled }
        if press.key == .delete { backspace(); return .handled }
        if press.key == .escape { clear(); return .handled }
        let allowed = "0123456789.+-*/^()!%,=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_ "
        let chars = press.characters.filter { allowed.contains($0) }
        guard !chars.isEmpty else { return .ignored }
        type(chars.replacingOccurrences(of: "*", with: "×").replacingOccurrences(of: "/", with: "÷"))
        return .handled
    }
}

/// Keys dim slightly while pressed.
private struct PressableKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Floating calculator

/// A small calculator that floats over a notebook. Drag it by its handle,
/// collapse it to a bar, or close it.
struct FloatingCalculator: View {
    let onInsert: (String) -> Void
    let onClose: () -> Void
    @AppStorage("floatingCalculatorCollapsed") private var collapsed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Capsule().fill(.secondary.opacity(0.5)).frame(width: 30, height: 5)
                Text("Calculator").font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    withAnimation(.snappy) { collapsed.toggle() }
                } label: {
                    Image(systemName: collapsed ? "chevron.down" : "chevron.up").frame(width: 28, height: 28)
                }
                .accessibilityLabel(collapsed ? "Expand" : "Collapse")
                Button(action: onClose) {
                    Image(systemName: "xmark").frame(width: 28, height: 28)
                }
                .accessibilityLabel("Hide Calculator")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())

            if !collapsed {
                CalculatorPad(compact: true, onInsert: onInsert)
                    .padding([.horizontal, .bottom], 10)
                    .transition(.opacity)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.separator.opacity(0.6)))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
    }
}
