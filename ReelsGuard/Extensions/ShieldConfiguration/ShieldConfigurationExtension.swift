import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Text shown by iOS when the user opens the native Instagram app while it is
/// locked through Screen Time. Screen Time can only shield a whole app; it
/// cannot see or filter individual Reels inside it.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        Self.configuration
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        Self.configuration
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        Self.configuration
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        Self.configuration
    }

    private static let configuration = ShieldConfiguration(
        backgroundBlurStyle: .systemMaterial,
        title: ShieldConfiguration.Label(text: "Instagram is locked", color: .label),
        subtitle: ShieldConfiguration.Label(
            text: "Reels can't be filtered inside the Instagram app. Open Instagram from Reels Guard to watch only the Reels you choose.",
            color: .secondaryLabel
        ),
        primaryButtonLabel: ShieldConfiguration.Label(text: "OK", color: .white),
        primaryButtonBackgroundColor: .systemBlue
    )
}
