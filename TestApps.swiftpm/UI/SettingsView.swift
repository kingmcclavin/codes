import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var library: AppLibraryManager
    @EnvironmentObject var runtime: RuntimeManager
    @Environment(\.dismiss) private var dismiss

    @State private var showLibraryList = false
    @State private var newFolderName = ""
    @State private var showNewFolder = false

    var body: some View {
        NavigationStack {
            List {
                Section("Library") {
                    LabeledContent("Apps", value: "\(library.apps.count)")
                    LabeledContent("Total builds",
                                   value: "\(library.apps.reduce(0) { $0 + $1.versions.count })")
                    LabeledContent("Storage used",
                                   value: ByteCountFormatter.string(
                                        fromByteCount: ContainerStorage.shared.totalLibrarySize(),
                                        countStyle: .file))
                    NavigationLink("Manage Apps & Builds") { AppLibraryView() }
                }

                Section("Folders") {
                    ForEach(library.folders) { f in
                        Text(f.name)
                    }
                    Button {
                        showNewFolder = true
                    } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                }

                Section("Runtime") {
                    LabeledContent("Active runtime", value: runtime.activeRuntimeName)
                    Text(runtime.activeRuntimeCapabilities)
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("About the Runtime Limitation") {
                    Text("""
                    This container is a Swift Playgrounds–built app running in the \
                    normal iOS sandbox. iOS does not allow such an app to load and \
                    execute another app's signed native binary, and this project \
                    deliberately does not attempt to bypass Apple's signing or \
                    security model. Imported builds are therefore stored, validated, \
                    version-managed, and inspected — not natively executed. The \
                    runtime is a swappable module, so a stronger capability can be \
                    added later without changing the rest of the app.
                    """)
                    .font(.caption).foregroundStyle(.secondary)
                }

                Section("Privacy") {
                    Label("Everything stays on this device. Nothing is uploaded.",
                          systemImage: "lock.fill")
                        .font(.subheadline)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("New Folder", isPresented: $showNewFolder) {
                TextField("Folder name", text: $newFolderName)
                Button("Cancel", role: .cancel) { newFolderName = "" }
                Button("Create") {
                    let name = newFolderName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { library.createFolder(name: name) }
                    newFolderName = ""
                }
            }
        }
    }
}
