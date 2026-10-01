import SwiftUI

/// Entry point. (File is named `TestAppsApp` to avoid colliding with the
/// `ContainerApp` *model* type.)
@main
struct TestAppsApp: App {
    @StateObject private var library = AppLibraryManager.shared
    @StateObject private var logger = DiagnosticLogger.shared
    @StateObject private var runtime = RuntimeManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(logger)
                .environmentObject(runtime)
        }
    }
}
