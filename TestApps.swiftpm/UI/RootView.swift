import SwiftUI

/// Top-level container: hosts the virtual Home Screen and the global sheets
/// (import, settings, debug console, app details, launch result), plus the
/// one-time safety acknowledgment gate.
struct RootView: View {
    @EnvironmentObject var library: AppLibraryManager

    @State private var showImporter = false
    @State private var showSettings = false
    @State private var showConsole = false
    @State private var detailApp: ContainerApp?
    @State private var launchContext: LaunchContext?
    @State private var importFlow: ImportFlowState?

    var body: some View {
        ZStack {
            HomeScreenView(
                onImport: { showImporter = true },
                onOpenDetails: { detailApp = $0 },
                onLaunch: { launch($0) },
                onOpenSettings: { showSettings = true },
                onOpenConsole: { showConsole = true }
            )

            if !library.hasAcknowledgedSafety {
                SafetyGateView { library.acknowledgeSafety() }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: library.hasAcknowledgedSafety)
        // Import picker
        .sheet(isPresented: $showImporter) {
            DocumentPicker(
                onPicked: { urls in
                    showImporter = false
                    Task { await runImport(urls: urls) }
                },
                onCancel: { showImporter = false }
            )
            .ignoresSafeArea()
        }
        // Settings
        .sheet(isPresented: $showSettings) { SettingsView() }
        // Debug console
        .sheet(isPresented: $showConsole) { DebugConsoleView() }
        // App details
        .sheet(item: $detailApp) { app in
            NavigationStack {
                AppDetailsView(appID: app.id,
                               onLaunch: { a in detailApp = nil; launch(a) })
            }
        }
        // Launch result (inspection / limitation)
        .sheet(item: $launchContext) { ctx in
            LaunchResultView(context: ctx)
        }
        // Version-conflict / duplicate import decision
        .sheet(item: $importFlow) { flow in
            ImportDecisionView(state: flow) { importFlow = nil }
        }
    }

    // MARK: Import

    @MainActor
    private func runImport(urls: [URL]) async {
        for url in urls {
            do {
                let outcome = try await library.importIPA(from: url)
                switch outcome {
                case .addedNewApp:
                    break // already on the home screen
                case .versionConflict(let existing, let staged):
                    importFlow = ImportFlowState(kind: .newVersion,
                                                 existing: existing, staged: staged)
                case .duplicateBuild(let existing, let staged):
                    importFlow = ImportFlowState(kind: .duplicate,
                                                 existing: existing, staged: staged)
                }
            } catch {
                DiagnosticLogger.shared.log(.importer, "Import failed: \(error.localizedDescription)")
                launchContext = LaunchContext(appID: nil,
                                              title: "Import Failed",
                                              message: error.localizedDescription,
                                              isError: true)
            }
        }
    }

    // MARK: Launch

    private func launch(_ app: ContainerApp) {
        library.noteLaunched(appID: app.id)
        Task {
            let result = await RuntimeManager.shared.attemptLaunch(app: app)
            await MainActor.run {
                switch result {
                case .launched:
                    launchContext = LaunchContext(appID: app.id,
                                                  title: "Running",
                                                  message: "\(app.displayLabel) is running.",
                                                  isError: false)
                case .inspectionOnly(let reason):
                    launchContext = LaunchContext(appID: app.id,
                                                  title: "Inspection Mode",
                                                  message: reason,
                                                  isError: false)
                }
            }
        }
    }
}

// MARK: - Supporting value types

struct LaunchContext: Identifiable {
    let id = UUID()
    let appID: UUID?
    let title: String
    let message: String
    let isError: Bool
}

struct ImportFlowState: Identifiable {
    enum Kind { case newVersion, duplicate }
    let id = UUID()
    let kind: Kind
    let existing: ContainerApp
    let staged: AppVersion
}
