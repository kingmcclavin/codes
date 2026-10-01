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

/// Settings section that packages the running app as an .ipa and lets you save it with the Files picker.
struct ExportAppSection: View
{
    @State
    private var isExporting = false
    
    @State
    private var isWorking = false
    
    @State
    private var ipaFile: IPAFile?
    
    @State
    private var status: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EXPORT APP")
                .font(.caption.weight(.heavy))
                .foregroundColor(.white.opacity(0.6))
            Text("Package Skyline Links as an .ipa file and save it to Files. The .ipa still has to be signed (for example with a sideloading tool) before it can be installed.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Button(action: export) {
                HStack {
                    if isWorking {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text(isWorking ? "EXPORTING…" : "EXPORT .IPA")
                }
            }
            .buttonStyle(BigButtonStyle())
            .disabled(isWorking)
            if let status = status {
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
        .fileExporter(isPresented: self.$isExporting, document: self.ipaFile, contentType: .ipa) { result in
            switch result {
            case .success(let url):
                status = "Saved \(url.lastPathComponent)"
            case .failure(let error):
                status = "Export cancelled or failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func export()
    {
        isWorking = true
        status = nil
        Task { @MainActor in
            do
            {
                let ipaPath = try await exportIPA()
                let ipaURL = URL(fileURLWithPath: ipaPath)
                
                self.ipaFile = try IPAFile(ipaURL: ipaURL)
                self.isExporting = true
            }
            catch
            {
                self.status = "Could not export .ipa: \(error.localizedDescription)"
            }
            self.isWorking = false
        }
    }
}
