import Foundation

/// Abstraction for "running" a guest app inside the container.
///
/// This protocol is deliberately the same shape the brief requested so the
/// runtime can be swapped/improved later without touching the Home Screen or
/// the IPA management code.
protocol AppRuntime {
    /// Short identifier for the diagnostic log and UI.
    var name: String { get }

    /// Human-readable statement of what this runtime can and cannot do.
    var capabilityDescription: String { get }

    /// Decide whether this runtime can launch a given app. Pure/synchronous so
    /// the compatibility checker and UI can call it freely.
    func canLaunch(_ metadata: AppMetadata) -> (Bool, reason: String)

    func prepare(app: ContainerApp) async throws
    func launch(app: ContainerApp) async throws
    func terminate(app: ContainerApp) async
}

/// Errors any runtime may throw. The UI surfaces `.message` verbatim.
enum RuntimeError: LocalizedError {
    case notSupported(String)
    case preparationFailed(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .notSupported(let m), .preparationFailed(let m), .launchFailed(let m):
            return m
        }
    }
}
