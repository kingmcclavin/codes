import FamilyControls
import SwiftUI

/// Screen Time lock for the native Instagram app.
struct NativeAppLockView: View {
    @EnvironmentObject private var screenTime: ScreenTimeController
    @EnvironmentObject private var model: SettingsModel
    @State private var showPicker = false
    @State private var errorMessage: String?

    private var lockedByStrictMode: Bool { model.settings.strictMode && screenTime.isLocked }

    var body: some View {
        Form {
            Section {
                Text("iOS doesn't let any app see or change what happens inside the Instagram app, so individual Reels can't be filtered there.")
                Text("What Screen Time can do is lock the whole Instagram app, so you use Instagram through Reels Guard or Safari, where Reels are filtered.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("In the Shortcuts app: Automation → + → App → Instagram → Is Opened → Run Immediately, then add the action Open App → Reels Guard.")
            } header: {
                Text("Gentler option: redirect with Shortcuts")
            } footer: {
                Text("Each time you open Instagram, iOS switches you to Reels Guard. Apps can't set this up for you; it has to be created in Shortcuts.")
            }

            if !screenTime.isAuthorized {
                Section {
                    Button("Allow Screen Time Access") {
                        Task {
                            do { try await screenTime.requestAuthorization() } catch { errorMessage = error.localizedDescription }
                        }
                    }
                } footer: {
                    Text("Uses Apple's Screen Time API on this device. Reels Guard gets an anonymous token for the app you pick and never sees which apps you use or what you do in them.")
                }
            } else {
                Section {
                    Button(screenTime.hasSelection ? "Change App" : "Choose the Instagram App") { showPicker = true }
                    if screenTime.hasSelection {
                        LabeledContent("Selected", value: "\(screenTime.selection.applicationTokens.count) app(s)")
                    }
                }
                Section {
                    Toggle("Lock the Instagram app", isOn: Binding(
                        get: { screenTime.isLocked },
                        set: { screenTime.setLocked($0) }
                    ))
                    .disabled(!screenTime.hasSelection || lockedByStrictMode)
                } footer: {
                    Text(lockedByStrictMode
                         ? "Turn off Strict Mode first to unlock the Instagram app."
                         : "This is a commitment device, not a parental control: you can always remove Screen Time access in Settings.")
                }
            }
        }
        .navigationTitle("Native Instagram App")
        .familyActivityPicker(isPresented: $showPicker, selection: $screenTime.selection)
        .alert("Screen Time access wasn't granted", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}
