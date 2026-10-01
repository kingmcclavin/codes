// swift-tools-version: 5.9

// Swift Playgrounds app package.
// Open the "SkylineLinks.swiftpm" folder in Swift Playgrounds on iPad and press Run.
// Swift Playgrounds may rewrite this file when you change app settings; that is fine.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Skyline Links",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Skyline Links",
            targets: ["AppModule"],
            bundleIdentifier: "com.skylinelinks.golf",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .leaf),
            accentColor: .presetColor(.green),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
