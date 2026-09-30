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
            // Stop above the home indicator so no key sits under it.
            let usable = CGSize(width: geo.size.width,
                                height: geo.size.height - geo.safeAreaInsets.bottom - 4)
            HStack(spacing: 0) {
                CalculatorView(availableSize: calculatorSize(in: usable),
                               onSettings: { showSettings = true },
                               onDebugger: { showDebuggerSheet = true })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if dockDebugger, let runner = controller.runner {
                    Divider()
                    DebuggerView(runner: runner)
                        .frame(width: min(420, geo.size.width * 0.42))
                }
            }
            .frame(width: usable.width, height: usable.height, alignment: .top)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .background(CalculatorView.bodyGradient.ignoresSafeArea())
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

/// The calculator body, filling the screen edge to edge: LCD with its bezel above
/// the keypad (portrait) or beside it (wide screens such as iPhone landscape).
/// App controls live in a pop-up menu (⋯) in the LCD bezel.
struct CalculatorView: View {
    @EnvironmentObject private var controller: EmulatorController
    let availableSize: CGSize
    let onSettings: () -> Void
    let onDebugger: () -> Void

    static let bodyGradient = LinearGradient(
        colors: [Color(red: 0.14, green: 0.14, blue: 0.15), Color(red: 0.08, green: 0.08, blue: 0.09)],
        startPoint: .top, endPoint: .bottom)

    /// Height of the strip at the top of the bezel that holds the menu button.
    private let menuStrip: CGFloat = 24
    private let margin: CGFloat = 6

    var body: some View {
        let wide = availableSize.width > availableSize.height * 1.15
        Group {
            if wide { landscape } else { portrait }
        }
        .frame(width: availableSize.width, height: availableSize.height)
    }

    // MARK: Portrait: LCD on top, keypad filling the rest of the screen

    private var portrait: some View {
        let width = availableSize.width - margin * 2
        let spacing: CGFloat = 8
        // The keypad gets at least ~62% of the height (like a phone calculator
        // layout); the 4:3 LCD takes the rest, narrowing if it has to.
        let minKeypad = max(KeyboardView.minimumHeight(forWidth: width), availableSize.height * 0.62)
        let maxScreenHeight = availableSize.height - minKeypad - spacing - margin
        let screenWidth = min(width, lcdWidth(forScreenHeight: maxScreenHeight))
        let screenHeight = screenHeightFor(width: screenWidth)
        let keypadHeight = availableSize.height - screenHeight - spacing - margin
        return VStack(spacing: spacing) {
            screen(width: screenWidth)
            KeyboardView(width: width, height: keypadHeight,
                         onPress: controller.press, onRelease: controller.release)
        }
        .padding(.horizontal, margin)
        .padding(.bottom, margin)
        .frame(width: availableSize.width, height: availableSize.height, alignment: .top)
    }

    // MARK: Landscape: screen beside keypad

    private var landscape: some View {
        let height = availableSize.height - margin * 2
        let keypadWidth = min(availableSize.width * 0.46, keypadWidthFitting(height: height))
        let screenWidth = min(availableSize.width - keypadWidth - margin * 3,
                              lcdWidth(forScreenHeight: height))
        return HStack(spacing: margin * 2) {
            screen(width: screenWidth)
                .frame(maxWidth: .infinity)
            KeyboardView(width: keypadWidth, height: height,
                         onPress: controller.press, onRelease: controller.release)
        }
        .padding(margin)
        .frame(width: availableSize.width, height: availableSize.height)
    }

    private func keypadWidthFitting(height: CGFloat) -> CGFloat {
        var lo: CGFloat = 150, hi: CGFloat = 900
        for _ in 0..<20 {
            let mid = (lo + hi) / 2
            if KeyboardView.minimumHeight(forWidth: mid) <= height { lo = mid } else { hi = mid }
        }
        return lo
    }

    // MARK: Screen with bezel and menu

    private func bezel(for width: CGFloat) -> CGFloat { max(4, width * 0.015) }

    private func screenHeightFor(width: CGFloat) -> CGFloat {
        let b = bezel(for: width)
        return (width - b * 2) * 0.75 + b + menuStrip
    }

    private func lcdWidth(forScreenHeight height: CGFloat) -> CGFloat {
        // Inverse of screenHeightFor (bezel ≈ 1.5% of width).
        var lo: CGFloat = 80, hi: CGFloat = 2000
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if screenHeightFor(width: mid) <= height { lo = mid } else { hi = mid }
        }
        return lo
    }

    /// LCD (4:3) inside a black bezel whose top strip carries the ⋯ menu.
    private func screen(width: CGFloat) -> some View {
        let b = bezel(for: width)
        let lcdWidth = width - b * 2
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                if controller.isPaused {
                    Text(controller.breakpointAddress.map { String(format: "BREAK %06X", $0) } ?? "PAUSED")
                        .font(.caption2.monospaced().bold())
                        .foregroundColor(.orange)
                } else if controller.speed != .normal {
                    Text("\(controller.speedPercent)%")
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                }
                Spacer()
                appMenu {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color(white: 0.6))
                        .frame(width: 44, height: menuStrip)
                        .contentShape(Rectangle())
                }
            }
            .padding(.leading, b + 4)
            .frame(height: menuStrip)
            if let runner = controller.runner {
                LCDView(runner: runner, pixelGrid: controller.showPixelGrid)
                    .frame(width: lcdWidth, height: lcdWidth * 0.75)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .contextMenu { menuItems }          // long-press the LCD for the menu too
            }
        }
        .padding(.bottom, b)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: max(8, width * 0.03), style: .continuous)
                        .fill(Color(white: 0.03)))
    }

    private func appMenu<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        let content = label()
        return Menu { menuItems } label: { content }
            .accessibilityLabel("Menu")
    }

    @ViewBuilder private var menuItems: some View {
        Button {
            controller.togglePause()
        } label: {
            Label(controller.isPaused ? "Resume" : "Pause",
                  systemImage: controller.isPaused ? "play.fill" : "pause.fill")
        }
        Button(action: onSettings) {
            Label("Settings", systemImage: "gearshape")
        }
        if controller.debuggerEnabled {
            Button(action: onDebugger) {
                Label("Debugger", systemImage: "ladybug")
            }
        }
        Divider()
        Button {
            controller.resetCalculator()
        } label: {
            Label("Reset Calculator", systemImage: "arrow.counterclockwise")
        }
    }
}
