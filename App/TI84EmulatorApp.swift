import SwiftUI
import TI84EmulatorUI

/// iOS / iPadOS app shell. All emulation lives in the TI84EmulatorCore
/// package; the UI lives in TI84EmulatorUI.
@main
struct TI84EmulatorApp: App {
    var body: some Scene {
        WindowGroup {
            CalculatorRootView()
        }
    }
}
