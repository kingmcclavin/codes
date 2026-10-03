import SwiftUI

@main
struct StudyOSApp: App {
    @StateObject private var store = AcademicStore()
    @StateObject private var navigation = AppNavigation()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(navigation)
        }
        .onChange(of: scenePhase) { _, phase in
            // Make sure nothing is lost when the app is closed or suspended.
            if phase != .active { store.saveNow() }
        }
    }
}
