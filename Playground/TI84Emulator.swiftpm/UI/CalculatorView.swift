#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UniformTypeIdentifiers

/// Entry point for the app: loads the ROM, shows the calculator and wires
/// app lifecycle events to persistence.
public struct CalculatorRootView: View {
    @StateObject private var model = EmulatorViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var importing = false

    public init() {}

    public var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.09).ignoresSafeArea()
            switch model.phase {
            case .loading:
                ProgressView().tint(.white)
            case let .needsROM(reason):
                romPrompt(reason)
            case let .failed(reason):
                romPrompt(reason)
            case .ready:
                CalculatorView(model: model)
            }
        }
        .preferredColorScheme(.dark)
        .task { model.start() }
        .onChange(of: scenePhase) { phase in model.scenePhaseChanged(phase) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            if case let .success(url) = result { model.importROM(from: url) }
        }
    }

    private func romPrompt(_ reason: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "memorychip")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("TI-84 Plus ROM needed")
                .font(.title2.bold())
            Text(reason)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Import ROM…") { importing = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: 480)
    }
}

/// The calculator: body, LCD and keypad, laid out for the current size.
struct CalculatorView: View {
    @ObservedObject var model: EmulatorViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingSettings = false
    @State private var showingDebugger = false

    /// Keypad height ≈ 1.6 × its width; the full calculator ≈ 2.35 × width,
    /// close to the real TI-84 Plus proportions.
    private static let keypadAspect: CGFloat = 1.6
    private static let bodyAspect: CGFloat = 2.35

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let sideBySide = size.width > size.height * 1.15 && size.height < 560
            let showPanel = model.settings.showDebugger && horizontalSizeClass == .regular && size.width > 900

            HStack(spacing: 0) {
                Group {
                    if sideBySide {
                        landscape(size)
                    } else {
                        portrait(CGSize(width: showPanel ? size.width - 380 : size.width, height: size.height))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showPanel {
                    DebuggerView(model: model)
                        .frame(width: 380)
                        .background(Color(white: 0.08))
                }
            }
            .background(HardwareKeyboardReader(onPress: model.keypad.press, onRelease: model.keypad.release).frame(width: 0, height: 0))
            .overlay(alignment: .topTrailing) { toolbar }
            .overlay(alignment: .top) { messageBanner }
        }
        .sheet(isPresented: $showingSettings) { SettingsView(model: model) }
        .sheet(isPresented: $showingDebugger) { NavigationStack { DebuggerView(model: model) } }
    }

    // MARK: Layouts

    private func portrait(_ size: CGSize) -> some View {
        let width = max(200, min(size.width - 24, (size.height - 24) / Self.bodyAspect))
        return calculatorBody(width: width)
    }

    private func landscape(_ size: CGSize) -> some View {
        let keypadWidth = max(180, min(size.width * 0.48, (size.height - 24) / Self.keypadAspect))
        return HStack(spacing: 20) {
            LCDBezel(frame: model.frame)
                .frame(maxWidth: size.width - keypadWidth - 60)
            KeyboardView(width: keypadWidth, onPress: model.keypad.press, onRelease: model.keypad.release,
                         haptics: model.settings.haptics)
        }
        .padding(12)
    }

    private func calculatorBody(width: CGFloat) -> some View {
        let inner = width * 0.90
        return VStack(spacing: width * 0.035) {
            LCDBezel(frame: model.frame)
                .frame(width: inner)
            HStack {
                Text("TI-84 Plus")
                    .font(.system(size: width * 0.045, weight: .heavy, design: .rounded))
                    .italic()
                    .foregroundColor(Color(white: 0.85))
                Spacer()
                Text(model.rom?.model == .ti84PlusSE ? "Silver Edition" : "")
                    .font(.system(size: width * 0.03, weight: .semibold))
                    .foregroundColor(Color(white: 0.6))
            }
            .frame(width: inner)
            KeyboardView(width: inner, onPress: model.keypad.press, onRelease: model.keypad.release,
                         haptics: model.settings.haptics)
        }
        .padding(.vertical, width * 0.06)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: width * 0.08, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.18, blue: 0.24),
                                              Color(red: 0.08, green: 0.09, blue: 0.12)],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.6), radius: 12, y: 6)
        )
    }

    // MARK: Chrome

    private var toolbar: some View {
        HStack(spacing: 12) {
            if model.settings.showDebugger {
                Button { showingDebugger = true } label: { Image(systemName: "ladybug") }
                    .accessibilityLabel("Debugger")
            }
            Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Settings")
        }
        .font(.title3)
        .foregroundColor(.white.opacity(0.7))
        .padding(12)
    }

    @ViewBuilder
    private var messageBanner: some View {
        if let message = model.message {
            Text(message)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.8)))
                .foregroundColor(.white)
                .padding(.top, 8)
                .onTapGesture { model.message = nil }
                .task(id: message) {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    if model.message == message { model.message = nil }
                }
        }
    }
}
#endif
