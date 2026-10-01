import SwiftUI

/// Presented after a launch attempt. Because the current runtime cannot execute
/// a guest's native code, this honestly explains the limitation and offers the
/// inspection view instead of faking a running app.
struct LaunchResultView: View {
    @EnvironmentObject var library: AppLibraryManager
    @Environment(\.dismiss) private var dismiss
    let context: LaunchContext

    private var app: ContainerApp? {
        context.appID.flatMap { library.binding(for: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: context.isError ? "xmark.octagon.fill"
                                                       : "sparkles.rectangle.stack")
                        .font(.system(size: 48))
                        .foregroundStyle(context.isError ? .red : .blue)
                        .padding(.top, 24)

                    Text(context.title).font(.title2.bold())

                    if let app {
                        AppIconView(app: app, size: 64)
                        Text(app.displayLabel).font(.headline)
                    }

                    Text(context.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if let app {
                        InspectionPreview(app: app)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        if let app { Task { await RuntimeManager.shared.terminate(app: app) } }
                        dismiss()
                    }
                }
            }
        }
    }
}

/// A read-only "what this app is" panel shown in place of a real running app.
struct InspectionPreview: View {
    let app: ContainerApp
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Inspection").font(.headline)
            let m = app.activeVersion.metadata
            row("Bundle ID", m.bundleIdentifier)
            row("Version", m.versionLabel)
            row("Min iOS", m.minimumOSVersion)
            row("Arch", m.architectures.isEmpty ? "unknown" : m.architectures.joined(separator: ", "))
            row("Size", m.formattedBundleSize)
            if !m.appExtensions.isEmpty { row("Extensions", m.appExtensions.joined(separator: ", ")) }
            Text("The build is stored, validated, and its data container is ready. When a runtime capable of executing this build becomes available, Launch will use it automatically.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Text(v).textSelection(.enabled)
            Spacer()
        }
        .font(.subheadline)
    }
}

/// One-time safety acknowledgment the brief requires before importing.
struct SafetyGateView: View {
    let onAcknowledge: () -> Void
    @State private var checked = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 44)).foregroundStyle(.orange)
                Text("Before You Import")
                    .font(.title2.bold())
                VStack(alignment: .leading, spacing: 12) {
                    bullet("Imported apps are NOT sandboxed from each other the way independently-installed iOS apps are. Isolation here is best-effort inside this one container.")
                    bullet("Only import apps you trust — ideally only apps you build yourself.")
                    bullet("Nothing you import, and no app data, is ever uploaded anywhere. Everything stays on this device.")
                    bullet("This container does not bypass Apple's signing or security model. Where iOS prevents an operation, it is reported, not worked around.")
                }
                .font(.subheadline)

                Toggle("I understand and accept these limitations.", isOn: $checked)
                    .font(.subheadline)

                Button {
                    onAcknowledge()
                } label: {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!checked)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(24)
            .frame(maxWidth: 520)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            Text(text)
        }
    }
}
