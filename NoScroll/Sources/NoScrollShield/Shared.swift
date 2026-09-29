import ManagedSettings

extension ManagedSettingsStore.Name {
    static let noscroll = Self("noscroll")
}

enum AppGroup {
    /// Shared between the app and its three Screen Time extensions.
    static let identifier = "group.app.noscroll"
}
