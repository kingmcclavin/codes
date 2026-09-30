import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var controller: EmulatorController

    var body: some View {
        ZStack {
            Color(white: 0.06).ignoresSafeArea()
            switch controller.phase {
            case .needsROM:
                ROMSetupView(message: nil)
            case .failed(let message):
                ROMSetupView(message: message)
            case .running:
                CalculatorScreen()
            }
        }
    }
}
