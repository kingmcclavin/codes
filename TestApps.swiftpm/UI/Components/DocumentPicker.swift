import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Wraps `UIDocumentPickerViewController` so the user can pick `.ipa` files from
/// the Files app. Uses `asCopy: true` so we receive a readable copy in our own
/// temp area regardless of the source (iCloud, On My iPad, third-party providers).
struct DocumentPicker: UIViewControllerRepresentable {
    let onPicked: ([URL]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Accept our custom IPA type plus generic archives/data, since many
        // providers report .ipa as a plain zip or data file.
        var types: [UTType] = []
        if let ipa = UTType("dev.local.testapps.ipa") { types.append(ipa) }
        types.append(contentsOf: [.zip, .data, .item])
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            parent.onPicked(urls)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}

/// Wraps `UIActivityViewController` for exporting diagnostics / preserving data.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
