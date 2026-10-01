import Foundation

/// The runtime that actually ships today.
///
/// WHY THIS IS ALL WE CAN DO (and why we say so plainly):
///
/// A Swift Playgrounds–built app runs as an ordinary App Store–model iOS
/// application. iOS only executes Mach-O code that is:
///   • code-signed with a trusted signature the kernel accepts, AND
///   • loaded through the system loader at launch (apps get no `fork`/`exec`,
///     no permission to `dlopen` arbitrary unsigned/foreign Mach-O, and no JIT
///     unless granted the dynamic-codesigning entitlement, which sandboxed
///     third-party apps do not get).
///
/// A guest `.ipa` is signed for *its own* bundle id and provisioning, not for
/// execution inside our process. We cannot re-sign it (that needs Apple signing
/// infrastructure we deliberately do not touch), and we cannot ask the kernel to
/// run foreign code from our sandbox. Projects like LiveContainer rely on
/// contexts a normal Swift Playgrounds app does not have (TrollStore /
/// sideloading with special entitlements, JIT via a debugger, or a jailbreak).
///
/// So this runtime does NOT pretend to execute the guest binary. It performs the
/// legitimate, useful work that IS available to a sandboxed app:
///   • fully parse and validate the build,
///   • prepare the isolated data directory,
///   • surface a static "what this app is" inspection view,
/// and it reports the execution limitation honestly.
///
/// The protocol shape means a stronger runtime (e.g. an embedded interpreter for
/// apps you build *as* interpretable content, or a future OS capability) can be
/// dropped in later without changing anything else.
final class InspectionRuntime: AppRuntime {
    let name = "Inspection Runtime"

    let capabilityDescription = """
    Imports, validates, inspects, and manages builds. It can prepare each \
    build's isolated data directory and show full metadata. It cannot execute \
    a guest app's native code, because iOS does not allow a sandboxed \
    (Swift Playgrounds–built) app to load and run another app's signed binary.
    """

    func canLaunch(_ metadata: AppMetadata) -> (Bool, reason: String) {
        (false, """
        This application cannot be launched by the current runtime.

        Reason: The required executable-loading capability is unavailable in \
        this environment. iOS does not permit a sandboxed app to load and run \
        another app's native Mach-O binary. The IPA can still be stored, \
        inspected, version-managed, and have its data container prepared.
        """)
    }

    func prepare(app: ContainerApp) async throws {
        let v = app.activeVersion
        DiagnosticLogger.shared.log(.launch, "Preparing \(app.displayLabel) \(v.displayVersion)")
        // Ensure the isolated data directory exists.
        _ = try ContainerStorage.shared.makeDataDirectory(
            bundleID: app.bundleIdentifier, versionID: v.id)
        DiagnosticLogger.shared.log(.loading, "Data container ready at \(v.dataRelativePath)")
    }

    func launch(app: ContainerApp) async throws {
        let v = app.activeVersion
        DiagnosticLogger.shared.log(.launch, "Launch requested: \(app.displayLabel) \(v.displayVersion)")
        let (ok, reason) = canLaunch(v.metadata)
        if !ok {
            DiagnosticLogger.shared.log(.runtime,
                "Native execution unavailable — entering inspection mode instead.")
            throw RuntimeError.notSupported(reason)
        }
        // (Unreachable today; present for when a stronger runtime is added.)
    }

    func terminate(app: ContainerApp) async {
        DiagnosticLogger.shared.log(.termination,
            "Inspection session ended for \(app.displayLabel)")
    }
}
