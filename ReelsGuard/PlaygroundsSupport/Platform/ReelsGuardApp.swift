import SwiftUI

@main
struct ReelsGuardApp: App {
    @StateObject private var model = SettingsModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ControlView()
                .environmentObject(model)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.reload() }
                }
        }
    }
}
