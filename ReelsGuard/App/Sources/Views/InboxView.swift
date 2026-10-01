import ReelsGuardCore
import SwiftUI

/// Reels the user explicitly shared into Reels Guard. Opening one plays that
/// Reel on its own; swiping on from it follows the normal rules.
struct InboxView: View {
    @EnvironmentObject private var model: SettingsModel
    @State private var pasted = ""
    @State private var invalidLink = false

    var body: some View {
        List {
            Section {
                TextField("Paste a Reel link", text: $pasted)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(pasted.isEmpty)
            } footer: {
                Text("In Instagram, tap Share on a Reel a friend sent you, then choose Reels Guard. Only the link is saved, on this device.")
            }

            Section {
                if model.inbox.isEmpty {
                    Text("Nothing here yet.").foregroundStyle(.secondary)
                }
                ForEach(model.inbox) { item in
                    Button {
                        model.open(item.url)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.url.path).lineLimit(1)
                            Text(item.receivedAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: model.removeShared)
            }
        }
        .navigationTitle("Shared with me")
        .alert("That isn't a link to an Instagram Reel or post.", isPresented: $invalidLink) {
            Button("OK", role: .cancel) {}
        }
    }

    private func add() {
        if model.addSharedLink(pasted) {
            pasted = ""
        } else {
            invalidLink = true
        }
    }
}
