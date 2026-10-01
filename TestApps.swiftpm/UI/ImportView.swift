import SwiftUI

/// Shown when an imported IPA's bundle id already exists — the "New Version
/// Detected" decision from the brief (Replace / Keep Both / Cancel), plus the
/// duplicate-build case.
struct ImportDecisionView: View {
    @EnvironmentObject var library: AppLibraryManager
    @Environment(\.dismiss) private var dismiss

    let state: ImportFlowState
    let onFinish: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: state.kind == .newVersion ? "shippingbox.and.arrow.backward" : "doc.on.doc")
                    .font(.system(size: 44))
                    .foregroundStyle(.blue)
                    .padding(.top, 24)

                Text(state.kind == .newVersion ? "New Version Detected" : "Duplicate Build")
                    .font(.title2.bold())

                Text(state.existing.displayLabel)
                    .font(.headline)

                VStack(spacing: 6) {
                    comparisonRow("Installed",
                                  "Build \(state.existing.activeVersion.buildNumber) (v\(state.existing.activeVersion.version))")
                    comparisonRow("New",
                                  "Build \(state.staged.buildNumber) (v\(state.staged.version))")
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                if state.kind == .duplicate {
                    Text("A build with this version and build number already exists. You can still keep both copies.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        library.replaceActiveBuild(appID: state.existing.id, staged: state.staged)
                        finish()
                    } label: {
                        Text("Replace Existing").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        library.keepBothBuilds(appID: state.existing.id, staged: state.staged)
                        finish()
                    } label: {
                        Text("Keep Both").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .cancel) {
                        library.discardStaged(state.staged, bundleID: state.existing.bundleIdentifier)
                        finish()
                    } label: {
                        Text("Cancel").frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 12)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
    }

    private func comparisonRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }

    private func finish() {
        dismiss()
        onFinish()
    }
}
