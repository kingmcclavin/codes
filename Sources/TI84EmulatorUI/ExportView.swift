#if canImport(SwiftUI) && canImport(UIKit)
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let ipa = UTType(filenameExtension: "ipa") ?? .zip
}

struct IPAFile: FileDocument {
    let file: FileWrapper

    static var readableContentTypes: [UTType] { [.ipa] }
    static var writableContentTypes: [UTType] { [.ipa] }

    init(ipaURL: URL) throws {
        self.file = try FileWrapper(url: ipaURL, options: .immediate)
    }

    init(configuration: ReadConfiguration) throws {
        self.file = configuration.file
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        file
    }
}

/// Exports this app as an .ipa with a custom home-screen name and icon, for
/// installing with a sideloading tool (AltStore, SideStore, ...).
struct ExportView: View {
    @State private var appName = "TI-84 Plus"
    @State private var bundleIdentifier = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var iconImage: UIImage?
    @State private var importingIconFile = false

    @State private var isWorking = false
    @State private var isExporting = false
    @State private var ipaFile: IPAFile?
    @State private var ipaFileName = "App.ipa"
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("App name", text: $appName)
                    .autocorrectionDisabled()
            } header: {
                Text("Name")
            } footer: {
                Text("Shown under the icon on the home screen.")
            }

            Section {
                HStack(spacing: 16) {
                    iconPreview
                    VStack(alignment: .leading, spacing: 10) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Choose from Photos", systemImage: "photo")
                        }
                        Button {
                            importingIconFile = true
                        } label: {
                            Label("Choose from Files", systemImage: "folder")
                        }
                        if iconImage != nil {
                            Button(role: .destructive) {
                                iconImage = nil
                                photoItem = nil
                            } label: {
                                Label("Use Default Icon", systemImage: "xmark.circle")
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            } header: {
                Text("App Icon")
            } footer: {
                Text("A square image works best (1024 × 1024). It is cropped to fill the icon; transparent areas become white.")
            }

            Section {
                TextField("Default: \(defaultBundleIdentifier)", text: $bundleIdentifier)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
            } header: {
                Text("Bundle Identifier (optional)")
            } footer: {
                Text("Change it to install the exported app alongside another copy.")
            }

            Section {
                Button(action: export) {
                    HStack {
                        Label("Export IPA", systemImage: "square.and.arrow.up")
                            .imageScale(.large)
                        Spacer()
                        if isWorking { ProgressView() }
                    }
                }
                .disabled(isWorking || appName.trimmingCharacters(in: .whitespaces).isEmpty)
            } footer: {
                Text(statusMessage ?? "The .ipa is unsigned. Install it with a sideloading tool such as AltStore or SideStore, which signs it with your Apple ID.")
            }
        }
        .navigationTitle("Export App")
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    iconImage = image
                }
            }
        }
        .fileImporter(isPresented: $importingIconFile, allowedContentTypes: [.image]) { result in
            guard case let .success(url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                iconImage = image
            }
        }
        .fileExporter(isPresented: $isExporting, document: ipaFile, contentType: .ipa,
                      defaultFilename: ipaFileName) { result in
            switch result {
            case let .success(url): statusMessage = "Saved \(url.lastPathComponent)."
            case let .failure(error): statusMessage = "Could not save: \(error.localizedDescription)"
            }
        }
    }

    private var defaultBundleIdentifier: String {
        (Bundle.main.bundleIdentifier ?? "com.example.app").replacingOccurrences(of: "swift-playgrounds-", with: "")
    }

    @ViewBuilder
    private var iconPreview: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if let iconImage {
            Image(uiImage: iconImage)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .background(Color.white)
                .clipShape(shape)
        } else {
            shape
                .fill(Color(white: 0.2))
                .frame(width: 72, height: 72)
                .overlay(Image(systemName: "app.dashed").font(.title).foregroundColor(.secondary))
        }
    }

    private func export() {
        isWorking = true
        statusMessage = "Building .ipa…"
        let options = IPAExportOptions(
            displayName: appName,
            icon: iconImage,
            bundleIdentifier: bundleIdentifier.isEmpty ? nil : bundleIdentifier)

        Task { @MainActor in
            defer { isWorking = false }
            do {
                let ipaPath = try await exportIPA(options: options)
                let ipaURL = URL(fileURLWithPath: ipaPath)

                ipaFileName = ipaURL.lastPathComponent
                ipaFile = try IPAFile(ipaURL: ipaURL)
                statusMessage = nil
                isExporting = true
            } catch {
                statusMessage = "Could not export .ipa: \(error.localizedDescription)"
            }
        }
    }
}
#endif
