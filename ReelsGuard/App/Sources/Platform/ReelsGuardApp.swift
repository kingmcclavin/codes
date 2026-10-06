import SwiftUI

@main
struct ReelsGuardApp: App {
    @StateObject private var model = SettingsModel()
    @StateObject private var screenTime = ScreenTimeController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(service: model.service)
                .environmentObject(model)
                .environmentObject(screenTime)
                .onOpenURL { model.handleOpenURL($0) }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    model.reload()
                    screenTime.refreshAuthorization()
                }
        }
    }
}
