import SwiftUI
import UniformTypeIdentifiers

// Export the running app as an .ipa file (Payload/<App>.app zipped), so it can be
// renamed, given an icon and installed with a sideloading / signing tool.

extension UTType {
    static let ipa = UTType(filenameExtension: "ipa") ?? .zip
}

/// Copies the running app bundle into Payload/, zips it and returns the .ipa path.
/// Returns a String because returning a URL from this async function has been seen
/// to crash in Swift Playgrounds.
func exportIPA() async throws -> String {
    let bundleURL = Bundle.main.bundleURL

    let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let payloadDirectory = temporaryDirectory.appendingPathComponent("Payload")
    try FileManager.default.createDirectory(at: payloadDirectory, withIntermediateDirectories: true, attributes: nil)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let appName = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String ?? "App"
    let appURL = payloadDirectory.appendingPathComponent("\(appName).app")
    let ipaURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(appName).ipa")

    try FileManager.default.copyItem(at: bundleURL, to: appURL)

    // Never ship a TI ROM inside the exported app: ROM images are copyrighted.
    // (An imported ROM lives in Application Support, so the app keeps working.)
    if let enumerator = FileManager.default.enumerator(at: appURL, includingPropertiesForKeys: nil) {
        for case let file as URL in enumerator where file.pathExtension.lowercased() == "rom" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // Apple forbids registering App IDs containing "swift-playgrounds-".
    let bundleID = Bundle.main.bundleIdentifier ?? "com.example.ti84ce-emulator"
    let updatedBundleID = bundleID.replacingOccurrences(of: "swift-playgrounds-", with: "")
    let plistURL = appURL.appendingPathComponent("Info.plist")
    let infoPlist = try NSMutableDictionary(contentsOf: plistURL, error: ())
    infoPlist[kCFBundleIdentifierKey as String] = updatedBundleID
    try infoPlist.write(to: plistURL)

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        // Coordinated read access "forUploading" zips the directory for us.
        let readIntent = NSFileAccessIntent.readingIntent(with: payloadDirectory, options: .forUploading)
        NSFileCoordinator().coordinate(with: [readIntent], queue: .main) { error in
            do {
                if let error { throw error }
                // Rename the zip to .ipa.
                _ = try FileManager.default.replaceItemAt(ipaURL, withItemAt: readIntent.url)
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    return ipaURL.path
}

struct IPAFile: FileDocument {
    let file: FileWrapper

    static var readableContentTypes: [UTType] { [.ipa] }
    static var writableContentTypes: [UTType] { [.ipa] }

    init(ipaURL: URL) throws {
        file = try FileWrapper(url: ipaURL, options: .immediate)
    }

    init(configuration: ReadConfiguration) throws {
        file = configuration.file
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        file
    }
}

/// Settings row that builds the .ipa and lets the user save it to Files.
struct ExportIPAButton: View {
    @State private var isWorking = false
    @State private var isExporting = false
    @State private var ipaFile: IPAFile?
    @State private var status: String?

    var body: some View {
        Button(action: export) {
            HStack {
                Label("Export app as .ipa", systemImage: "square.and.arrow.up")
                Spacer()
                if isWorking { ProgressView() }
            }
        }
        .disabled(isWorking)
        .fileExporter(isPresented: $isExporting, document: ipaFile, contentType: .ipa) { result in
            switch result {
            case .success(let url): status = "Saved \(url.lastPathComponent)"
            case .failure(let error): status = "Export failed: \(error.localizedDescription)"
            }
        }
        if let status {
            Text(status).font(.caption).foregroundColor(.secondary)
        }
    }

    private func export() {
        isWorking = true
        status = nil
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let ipaPath = try await exportIPA()
                ipaFile = try IPAFile(ipaURL: URL(fileURLWithPath: ipaPath))
                isExporting = true
            } catch {
                status = "Could not export .ipa: \(error.localizedDescription)"
            }
        }
    }
}
