import PhotosUI
import SwiftUI
import UIKit

struct CanvasRepresentable: UIViewControllerRepresentable {
    let editor: EditorModel

    func makeUIViewController(context: Context) -> CanvasViewController {
        CanvasViewController(editor: editor)
    }

    func updateUIViewController(_ controller: CanvasViewController, context: Context) {}
}

struct ImagePicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
            let onPick = parent.onPick
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage else { return }
                DispatchQueue.main.async { onPick(image) }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
