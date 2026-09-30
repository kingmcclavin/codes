import SwiftUI

@main
struct TI84CEApp: App {
    @StateObject private var controller = EmulatorController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                controller.enterForeground()
            case .inactive, .background:
                // Persist RAM, archive and machine state whenever we leave the foreground.
                controller.enterBackground()
            @unknown default:
                break
            }
        }
    }
}
