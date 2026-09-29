#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

/// Emulator preferences and memory management.
struct SettingsView: View {
    @ObservedObject var model: EmulatorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRAMReset = false
    @State private var confirmArchiveReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Emulation") {
                    Picker("Speed", selection: $model.settings.speed) {
                        Text("1× (real)").tag(1.0)
                        Text("2×").tag(2.0)
                        Text("4×").tag(4.0)
                        Text("Unlimited").tag(0.0)
                    }
                    VStack(alignment: .leading) {
                        Text("LCD response")
                        Slider(value: $model.settings.lcdPersistence, in: 0...0.8) {
                            Text("LCD response")
                        } minimumValueLabel: {
                            Text("Crisp").font(.caption)
                        } maximumValueLabel: {
                            Text("Slow").font(.caption)
                        }
                    }
                    Toggle("Haptic feedback", isOn: $model.settings.haptics)
                    Toggle("Developer debugger", isOn: $model.settings.showDebugger)
                }

                Section {
                    Button("Save State") { model.saveState() }
                    Button("Load State") { model.loadState() }
                    Button("Save RAM") { model.saveRAM() }
                    Button("Load RAM") { model.loadRAM() }
                } header: {
                    Text("Memory")
                } footer: {
                    Text("The calculator's memory is saved automatically when the app goes to the background and restored on launch.")
                }

                Section {
                    Button("Reset Calculator") { model.resetCalculator() }
                    Button("Reset RAM…", role: .destructive) { confirmRAMReset = true }
                    Button("Erase Archive…", role: .destructive) { confirmArchiveReset = true }
                } header: {
                    Text("Reset")
                } footer: {
                    Text("Reset Calculator is a hardware reset that keeps memory. Reset RAM clears RAM so the OS starts fresh. Erase Archive restores Flash from the original ROM image.")
                }

                if let rom = model.rom {
                    Section("ROM") {
                        LabeledContent("Model", value: rom.model.rawValue)
                        LabeledContent("Size", value: "\(rom.size / 1024) KB")
                        LabeledContent("CRC-32", value: hex(rom.crc32))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SHA-256")
                            Text(rom.sha256)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                        ForEach(rom.warnings, id: \.self) { warning in
                            Text(warning).font(.caption).foregroundColor(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Clear all RAM?", isPresented: $confirmRAMReset, titleVisibility: .visible) {
                Button("Reset RAM", role: .destructive) { model.resetRAM() }
            } message: {
                Text("Programs and variables that are not archived will be lost.")
            }
            .confirmationDialog("Erase the archive?", isPresented: $confirmArchiveReset, titleVisibility: .visible) {
                Button("Erase Archive", role: .destructive) { model.resetArchive() }
            } message: {
                Text("Archived programs, variables and apps installed after the ROM dump will be lost.")
            }
        }
    }
}
#endif
