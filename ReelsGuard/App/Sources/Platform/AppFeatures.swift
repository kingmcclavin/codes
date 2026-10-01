/// Which enforcement surfaces this build includes. The full Xcode build has
/// all of them; the Swift Playgrounds build (iPad) has only the in-app
/// browser, because Playgrounds can't build app extensions or use the
/// Family Controls entitlement.
enum AppFeatures {
    static let hasShareExtension = true
    static let hasSafariExtension = true
    static let hasScreenTime = true
}
