import SwiftUI

/// Top-level running screen: the calculator plus toolbar, settings and debugger.
struct CalculatorScreen: View {
    @EnvironmentObject private var controller: EmulatorController
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var showSettings = false
    @State private var showDebuggerSheet = false

    private var dockDebugger: Bool { controller.debuggerEnabled && hSize == .regular }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                CalculatorView(availableSize: calculatorSize(in: geo.size),
                               onSettings: { showSettings = true },
                               onDebugger: { showDebuggerSheet = true })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if dockDebugger, let runner = controller.runner {
                    Divider()
                    DebuggerView(runner: runner)
                        .frame(width: min(420, geo.size.width * 0.42))
                }
            }
        }
        .background(HardwareKeyboardCapture(onPress: controller.press, onRelease: controller.release)
                        .frame(width: 0, height: 0))
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(controller)
        }
        .sheet(isPresented: $showDebuggerSheet) {
            if let runner = controller.runner {
                NavigationStack {
                    DebuggerView(runner: runner)
                        .environmentObject(controller)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showDebuggerSheet = false }
                            }
                        }
                }
            }
        }
        .overlay(alignment: .bottom) { noticeBanner }
    }

    private func calculatorSize(in size: CGSize) -> CGSize {
        dockDebugger ? CGSize(width: size.width - min(420, size.width * 0.42), height: size.height) : size
    }

    @ViewBuilder private var noticeBanner: some View {
        if let notice = controller.notice {
            Text(notice)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 12)
                .onTapGesture { controller.notice = nil }
                .task(id: notice) {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if controller.notice == notice { controller.notice = nil }
                }
        }
    }
}

/// The calculator body: LCD with bezel above the keypad (portrait) or beside it
/// (wide screens such as iPhone landscape).
struct CalculatorView: View {
    @EnvironmentObject private var controller: EmulatorController
    let availableSize: CGSize
    let onSettings: () -> Void
    let onDebugger: () -> Void

    private let bodyColor = Color(red: 0.09, green: 0.09, blue: 0.10)
    private let faceColor = Color(red: 0.14, green: 0.14, blue: 0.15)

    var body: some View {
        let wide = availableSize.width > availableSize.height * 1.15
        Group {
            if wide { landscape } else { portrait }
        }
    }

    // MARK: Portrait: the physical calculator's proportions

    private var portrait: some View {
        // Choose the body width so screen + keypad fit the available height.
        let margin: CGFloat = 12
        let maxWidth = min(availableSize.width - margin * 2, 560)
        let width = fittedWidth(maxWidth: maxWidth, maxHeight: availableSize.height - margin * 2)
        let pad = width * 0.05
        let keypadWidth = width - pad * 2
        return VStack(spacing: width * 0.035) {
            header(width: width)
            screen(width: keypadWidth * 0.94)
            KeyboardView(width: keypadWidth, onPress: controller.press, onRelease: controller.release)
        }
        .padding(pad)
        .padding(.bottom, pad * 0.5)
        .background(
            RoundedRectangle(cornerRadius: width * 0.08, style: .continuous)
                .fill(LinearGradient(colors: [faceColor, bodyColor], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.6), radius: 18, y: 8)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Largest body width whose total height fits `maxHeight`.
    private func fittedWidth(maxWidth: CGFloat, maxHeight: CGFloat) -> CGFloat {
        func height(_ w: CGFloat) -> CGFloat {
            let pad = w * 0.05
            let kw = w - pad * 2
            let screenH = kw * 0.94 * 0.75 + kw * 0.94 * 0.12
            return pad * 2.5 + 28 + w * 0.07 + screenH + KeyboardView.height(forWidth: kw)
        }
        var lo: CGFloat = 200, hi = max(200, maxWidth)
        for _ in 0..<20 {
            let mid = (lo + hi) / 2
            if height(mid) <= maxHeight { lo = mid } else { hi = mid }
        }
        return lo
    }

    // MARK: Landscape: screen beside keypad

    private var landscape: some View {
        let h = availableSize.height - 24
        let keypadWidth = min(availableSize.width * 0.45, keypadWidthFitting(height: h))
        let screenWidth = min(availableSize.width - keypadWidth - 60, (h - 60) / 0.87)
        return HStack(spacing: 20) {
            VStack(spacing: 10) {
                header(width: screenWidth)
                screen(width: screenWidth)
            }
            KeyboardView(width: keypadWidth, onPress: controller.press, onRelease: controller.release)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [faceColor, bodyColor], startPoint: .leading, endPoint: .trailing))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func keypadWidthFitting(height: CGFloat) -> CGFloat {
        var lo: CGFloat = 150, hi: CGFloat = 900
        for _ in 0..<20 {
            let mid = (lo + hi) / 2
            if KeyboardView.height(forWidth: mid) <= height { lo = mid } else { hi = mid }
        }
        return lo
    }

    // MARK: Pieces

    private func header(width: CGFloat) -> some View {
        HStack(spacing: 12) {
            Text("TI-84 Plus CE")
                .font(.system(size: max(12, width * 0.045), weight: .heavy, design: .rounded))
                .italic()
                .foregroundColor(Color(white: 0.85))
            Spacer()
            if controller.isPaused {
                Text(controller.breakpointAddress.map { String(format: "BREAK %06X", $0) } ?? "PAUSED")
                    .font(.caption2.monospaced().bold())
                    .foregroundColor(.orange)
            } else if controller.speed != .normal {
                Text("\(controller.speedPercent)%")
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
            }
            toolbarButton(controller.isPaused ? "play.fill" : "pause.fill", label: controller.isPaused ? "Resume" : "Pause") {
                controller.togglePause()
            }
            if controller.debuggerEnabled {
                toolbarButton("ladybug", label: "Debugger", action: onDebugger)
            }
            toolbarButton("gearshape", label: "Settings", action: onSettings)
        }
        .frame(height: 28)
    }

    private func toolbarButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(white: 0.75))
                .frame(width: 30, height: 28)
        }
        .accessibilityLabel(label)
    }

    /// LCD with its bezel (4:3 display area).
    private func screen(width: CGFloat) -> some View {
        let bezel = width * 0.06
        let lcdWidth = width - bezel * 2
        return ZStack {
            RoundedRectangle(cornerRadius: width * 0.04, style: .continuous)
                .fill(Color(white: 0.04))
            if let runner = controller.runner {
                LCDView(runner: runner, pixelGrid: controller.showPixelGrid)
                    .frame(width: lcdWidth, height: lcdWidth * 0.75)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black, lineWidth: 1))
            }
        }
        .frame(width: width, height: lcdWidth * 0.75 + bezel * 2)
    }
}
