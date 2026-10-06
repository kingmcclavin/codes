import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Settings › Backup: save every notebook (with its folders) to Files, and
/// restore from such a backup.
struct BackupView: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var tabs: TabsModel
    @EnvironmentObject private var calc: CalculatorStore
    @AppStorage("backupFormat") private var formatRaw = BackupManager.Format.editable.rawValue
    @AppStorage("lastBackupDate") private var lastBackup = 0.0
    @State private var working = false
    @State private var exportURL: URL?
    @State private var pendingReport: BackupManager.Report?
    @State private var restoring = false
    @State private var message: String?

    private var format: BackupManager.Format { BackupManager.Format(rawValue: formatRaw) ?? .editable }

    var body: some View {
        Form {
            Section {
                Picker("Save Notebooks As", selection: $formatRaw) {
                    ForEach(BackupManager.Format.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Format")
            } footer: {
                Text(format == .editable
                     ? "Each notebook is saved as one .basis file with all its ink, text, images and pages. Restoring it gives you the notebook back fully editable — you can still erase or move anything written before the backup. Calculator data is included."
                     : "Each notebook is saved as a PDF you can open anywhere. PDFs can't be turned back into editable notebooks — choose Editable for a backup you can restore.")
            }

            Section {
                Button {
                    createBackup()
                } label: {
                    HStack {
                        Label("Back Up Notebooks…", systemImage: "externaldrive.badge.icloud")
                        Spacer()
                        if working { ProgressView() }
                    }
                }
                .disabled(working || store.summaries.isEmpty)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Creates a “Basis Backup” folder with one folder per library folder. Save it to iCloud Drive so it's safe even if the app is deleted.")
                    if lastBackup > 0 {
                        Text("Last backup: \(Date(timeIntervalSince1970: lastBackup).formatted(date: .abbreviated, time: .shortened))")
                    }
                }
            }

            Section {
                Button {
                    restoring = true
                } label: {
                    Label("Restore from Backup…", systemImage: "arrow.counterclockwise.circle")
                }
                .disabled(working)
            } footer: {
                Text("Choose a backup folder or individual .basis files. Folders are recreated in your library; notebooks you already have are skipped, nothing is overwritten.")
            }
        }
        .navigationTitle("Backup")
        .sheet(item: Binding(get: { exportURL.map(ExportedFolder.init) }, set: { if $0 == nil { exportURL = nil } })) { item in
            FolderExportPicker(url: item.url) { saved in
                if saved {
                    lastBackup = Date().timeIntervalSince1970
                    message = "Backed up " + (pendingReport?.summary ?? "your notebooks") + "."
                }
                exportURL = nil
                try? FileManager.default.removeItem(at: item.url)
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $restoring, allowedContentTypes: [.folder, .data, .item], allowsMultipleSelection: true) { result in
            guard case let .success(urls) = result, !urls.isEmpty else { return }
            let report = BackupManager.restore(from: urls, into: store, calculator: calc)
            message = report.notebooks == 0 && report.skipped == 0 && report.failed.isEmpty
                ? "No Basis notebooks were found there. Choose a backup folder or .basis files."
                : "Restored " + report.summary + "."
        }
        .alert("Backup", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func createBackup() {
        tabs.flushAll()
        working = true
        let library = BackupManager.snapshot(of: store)
        let format = self.format
        let calculatorData = format == .editable ? calc.exportData().flatMap { try? Data(contentsOf: $0) } : nil
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try BackupManager.createBackup(library, format: format, calculatorData: calculatorData) }
            }.value
            working = false
            switch result {
            case let .success((url, report)):
                pendingReport = report
                exportURL = url
            case let .failure(error):
                message = "The backup couldn't be created: \(error.localizedDescription)"
            }
        }
    }
}

private struct ExportedFolder: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Lets the user pick where to save a folder (Files, iCloud Drive, …).
private struct FolderExportPicker: UIViewControllerRepresentable {
    let url: URL
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onFinish(true) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onFinish(false) }
    }
}
