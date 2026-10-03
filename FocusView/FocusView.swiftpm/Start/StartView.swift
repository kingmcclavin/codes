import SwiftUI

/// The minimal start page: paste a URL, open it.
struct StartView: View {
    let onOpen: (URL) -> Void

    @State private var input = ""
    @State private var errorText: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 8) {
                Text("FOCUSVIEW")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .tracking(6)
                Text("Watch without the distractions.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "play.rectangle")
                        .foregroundStyle(.secondary)
                    TextField("Paste video URL", text: $input)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($fieldFocused)
                        .onSubmit(open)
                    if !input.isEmpty {
                        Button {
                            input = ""
                            errorText = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear")
                    }
                }
                .font(.title3)
                .padding(.horizontal, 18)
                .frame(minHeight: 60)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack(spacing: 12) {
                    PasteButton(payloadType: String.self) { strings in
                        guard let text = strings.first else { return }
                        DispatchQueue.main.async {
                            input = text
                            errorText = nil
                        }
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)

                    Button(action: open) {
                        Text("Open")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: 560)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }

    private func open() {
        guard let url = URLInputParser.url(from: input) else {
            errorText = "That doesn't look like a web address."
            return
        }
        errorText = nil
        fieldFocused = false
        onOpen(url)
    }
}
