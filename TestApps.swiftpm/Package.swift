// swift-tools-version: 5.9

// IMPORTANT: This manifest is written for **Swift Playgrounds on iPad**
// (App Playground / ".swiftpm" project). The `AppleProductTypes` module and
// the `.iOSApplication` product type below are provided *only* inside Swift
// Playgrounds and Xcode. This package will NOT resolve with a plain
// command-line `swift build` on Linux/macOS — that is expected and by design.
//
// To use this project:
//   1. Copy the whole `TestApps.swiftpm` folder onto your iPad
//      (via Files, iCloud Drive, AirDrop, or a Git client such as Working Copy).
//   2. Open it with Swift Playgrounds.
//   3. Press Run / Build.
//
// Everything in Sources uses only Foundation / SwiftUI / UIKit / Compression,
// all of which are available to a Swift Playgrounds-built app on iPadOS 16+.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "TestApps",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .iOSApplication(
            name: "TestApps",
            targets: ["AppModule"],
            bundleIdentifier: "dev.local.testapps",
            teamIdentifier: nil,
            displayVersion: "1.0",
            bundleVersion: "1",
            // appIcon intentionally omitted (defaults to a system placeholder) so
            // the manifest never fails over a cosmetic icon enum. Set one in
            // Swift Playgrounds' App Settings, or add `appIcon:` here later.
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            // The container needs to be able to open .ipa files from the Files app.
            // We declare a document-type / UTI import below via Info.plist additions.
            additionalInfoPlistContentFilePath: "Resources/Info.plist"
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: ".",
            exclude: [
                "README.md",
                // Info.plist is consumed by the product builder via
                // `additionalInfoPlistContentFilePath`, not compiled as a resource.
                "Resources/Info.plist"
            ]
        )
    ]
)
