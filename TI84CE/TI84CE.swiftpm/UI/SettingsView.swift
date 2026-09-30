import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var controller: EmulatorController
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var confirmResetRAM = false
    @State private var confirmErase = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Emulation") {
                    Picker("Speed", selection: $controller.speed) {
                        ForEach(EmulatorController.SpeedSetting.allCases) { Text($0.label).tag($0) }
                    }
                    LabeledContent("Measured speed", value: "\(controller.speedPercent)% of real time")
                    Toggle("Haptic key feedback", isOn: $controller.hapticsEnabled)
                    Toggle("LCD pixel grid", isOn: $controller.showPixelGrid)
                    Stepper("Battery level: \(controller.batteryLevel) / 4", value: $controller.batteryLevel, in: 0...4)
                }

                Section {
                    ForEach(EmulatorController.snapshotSlots, id: \.self) { slot in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Slot \(slot)")
                                Text(controller.snapshotDate(slot: slot).map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Empty")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Save") { controller.saveSnapshot(slot: slot) }
                                .buttonStyle(.bordered)
                            Button("Load") { controller.loadSnapshot(slot: slot); dismiss() }
                                .buttonStyle(.bordered)
                                .disabled(controller.snapshotDate(slot: slot) == nil)
                        }
                    }
                } header: {
                    Text("Memory (Save RAM / Load RAM)")
                } footer: {
                    Text("Calculator memory — RAM, archive and the complete machine state — is saved automatically whenever the app goes to the background and restored on launch. Slots keep extra snapshots.")
                }

                Section("Reset") {
                    Button("Reset calculator (keep RAM)") { controller.resetCalculator(); dismiss() }
                    Button("Reset RAM", role: .destructive) { confirmResetRAM = true }
                    Button("Erase archive and RAM", role: .destructive) { confirmErase = true }
                }

                Section("ROM") {
                    Text(controller.romDescription).font(.footnote.monospaced())
                    LabeledContent("Source", value: controller.romSourceLabel)
                    Button("Import a different ROM…") { importing = true }
                }

                Section("Developer") {
                    Toggle("Show debugger", isOn: $controller.debuggerEnabled)
                }

                Section("Hardware keyboard") {
                    ForEach(HardwareKeyMap.help, id: \.0) { item in
                        LabeledContent(item.0, value: item.1)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Clear all RAM? Unarchived variables and programs are lost.",
                                isPresented: $confirmResetRAM, titleVisibility: .visible) {
                Button("Reset RAM", role: .destructive) { controller.resetRAM(); dismiss() }
            }
            .confirmationDialog("Erase the archive and RAM, restoring the calculator to the ROM's original contents?",
                                isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) { controller.eraseEverything(); dismiss() }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    controller.importROM(from: url)
                    dismiss()
                }
            }
        }
    }
}
