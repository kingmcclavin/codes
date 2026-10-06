import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

extension UTType
{
    static let ipa = UTType(filenameExtension: "ipa")!
}

struct IPAFile: FileDocument
{
    let file: FileWrapper

    static var readableContentTypes: [UTType] { [.ipa] }
    static var writableContentTypes: [UTType] { [.ipa] }

    init(ipaURL: URL) throws
    {
        self.file = try FileWrapper(url: ipaURL, options: .immediate)
    }

    init(configuration: ReadConfiguration) throws
    {
        self.file = configuration.file
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper
    {
        return self.file
    }
}

/// Remembers the custom icon and name between exports.
enum ExportBranding {
    private static var iconURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("CustomAppIcon.png")
    }

    static var icon: UIImage? {
        get { (try? Data(contentsOf: iconURL)).flatMap(UIImage.init(data:)) }
        set {
            if let data = newValue?.pngData() {
                try? data.write(to: iconURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: iconURL)
            }
        }
    }

    static var displayName: String {
        get { UserDefaults.standard.string(forKey: "exportDisplayName") ?? "Basis" }
        set { UserDefaults.standard.set(newValue, forKey: "exportDisplayName") }
    }
}

/// Exports the running app as an .ipa for Sideloadly / AltStore, optionally
/// with a custom Home Screen icon and name.
struct ExportView: View
{
    @Environment(\.dismiss) private var dismiss

    @State private var icon: UIImage? = ExportBranding.icon
    @State private var displayName = ExportBranding.displayName
    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var isWorking = false
    @State private var isExporting = false
    @State private var ipaFile: IPAFile?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 20) {
                        iconPreview
                        VStack(alignment: .leading, spacing: 10) {
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Label("Choose from Photos", systemImage: "photo")
                            }
                            Button("Choose from Files", systemImage: "folder") { showFileImporter = true }
                            if icon != nil {
                                Button("Use Default Icon", systemImage: "arrow.uturn.backward", role: .destructive) {
                                    setIcon(nil)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("App Icon")
                } footer: {
                    Text("Square images work best (at least 1024 × 1024). Other shapes are center-cropped; transparent areas become white.")
                }

                Section("Home Screen Name") {
                    TextField("Basis", text: $displayName)
                        .onChange(of: displayName) { _, v in ExportBranding.displayName = v }
                }

                Section {
                    Button(action: export) {
                        HStack {
                            Label("Export IPA", systemImage: "square.and.arrow.up")
                                .imageScale(.large)
                                .foregroundColor(.accentColor)
                            Spacer()
                            if isWorking { ProgressView() }
                        }
                    }
                    .disabled(isWorking)
                } footer: {
                    Text("Save the .ipa to Files, then install it with Sideloadly or AltStore using your Apple ID.")
                }

                if let message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Export App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileExporter(isPresented: self.$isExporting, document: self.ipaFile, contentType: .ipa,
                          defaultFilename: fileName) { result in
                switch result {
                case .success: message = "Exported."
                case let .failure(error): message = "Export failed: \(error.localizedDescription)"
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image]) { result in
                guard case let .success(url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), let image = UIImage(data: data) { setIcon(image) }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { @MainActor in
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        setIcon(image)
                    }
                    photoItem = nil
                }
            }
        }
    }

    private var fileName: String {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Basis" : name
    }

    private var iconPreview: some View {
        Group {
            if let icon {
                Image(uiImage: AppIconWriter.squareOpaque(icon, pixels: 240))
                    .resizable()
            } else {
                // The app's built-in icon.
                Image("BasisLogo")
                    .resizable()
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.separator))
    }

    private func setIcon(_ image: UIImage?) {
        icon = image
        ExportBranding.icon = image
    }

    private func export()
    {
        isWorking = true
        message = nil
        let options = IPAExportOptions(icon: icon, displayName: displayName)
        Task { @MainActor in
            defer { isWorking = false }
            do
            {
                let ipaPath = try await exportIPA(options: options)
                let ipaURL = URL(fileURLWithPath: ipaPath)

                self.ipaFile = try IPAFile(ipaURL: ipaURL)
                self.isExporting = true
            }
            catch
            {
                print("Could not export .ipa:", error)
                message = "Could not export: \(error.localizedDescription)"
            }
        }
    }
}
