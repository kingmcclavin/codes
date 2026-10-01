import Foundation
import Combine

/// Chooses and drives the active `AppRuntime`. Today there is exactly one
/// (`InspectionRuntime`); the indirection exists so adding runtimes later is a
/// one-line change here rather than a rewrite.
@MainActor
final class RuntimeManager: ObservableObject {
    static let shared = RuntimeManager()

    enum LaunchResult {
        /// Native execution happened (not possible today).
        case launched
        /// Runtime could not execute the app; fall back to inspection UI.
        case inspectionOnly(reason: String)
    }

    @Published private(set) var runningBundleID: String?

    private let runtime: AppRuntime = InspectionRuntime()

    private init() {}

    var activeRuntimeName: String { runtime.name }
    var activeRuntimeCapabilities: String { runtime.capabilityDescription }

    /// Honest launchability for the compatibility checker / UI badges.
    nonisolated func launchability(for metadata: AppMetadata) -> (Bool, String) {
        let (ok, reason) = InspectionRuntime().canLaunch(metadata)
        return (ok, reason)
    }

    /// Attempt to launch; returns whether real execution happened or we fell
    /// back to inspection. Never throws to the UI — the result is the signal.
    func attemptLaunch(app: ContainerApp) async -> LaunchResult {
        do {
            try await runtime.prepare(app: app)
            try await runtime.launch(app: app)
            runningBundleID = app.bundleIdentifier
            DiagnosticLogger.shared.log(.launch, "Application launched: \(app.displayLabel)")
            return .launched
        } catch let RuntimeError.notSupported(reason) {
            DiagnosticLogger.shared.log(.runtime, "Exit reason: runtime unsupported")
            return .inspectionOnly(reason: reason)
        } catch {
            DiagnosticLogger.shared.log(.crash, "Launch error: \(error.localizedDescription)")
            return .inspectionOnly(reason: error.localizedDescription)
        }
    }

    func terminate(app: ContainerApp) async {
        await runtime.terminate(app: app)
        if runningBundleID == app.bundleIdentifier { runningBundleID = nil }
    }
}
