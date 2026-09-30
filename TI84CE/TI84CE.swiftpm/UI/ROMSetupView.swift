import SwiftUI
import UniformTypeIdentifiers

/// Shown until a ROM is available: explains what is needed and imports a ROM dump
/// with the Files picker.
struct ROMSetupView: View {
    @EnvironmentObject private var controller: EmulatorController
    let message: String?
    @State private var importing = false

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "cpu")
                .font(.system(size: 54, weight: .light))
                .foregroundColor(.accentColor)
            Text("TI-84 Plus CE Emulator")
                .font(.title.bold())
            Text("This app emulates the calculator's hardware — the eZ80 processor, memory, LCD, keypad and timers. The calculator's operating system comes from a ROM image of your own TI-84 Plus CE.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 520)
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
            Button {
                importing = true
            } label: {
                Label("Import ROM…", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .padding(.horizontal, 20).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            Text("Accepted: a 4 MB TI-84 Plus CE ROM dump (.rom). You can also add it to the project's Resources folder in Swift Playgrounds.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .padding(32)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                controller.importROM(from: url)
            }
        }
    }
}
