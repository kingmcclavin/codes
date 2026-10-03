import SwiftUI

@main
struct StudyOSApp: App {
    @StateObject private var store: AcademicStore = {
        let store = AcademicStore()
        // Launch argument `-StudyOSSampleData YES` fills an empty install with sample
        // data (used by automated screenshot runs). It never replaces existing data.
        if UserDefaults.standard.bool(forKey: "StudyOSSampleData") && store.db.courses.isEmpty {
            store.loadSampleData()
        }
        return store
    }()
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
