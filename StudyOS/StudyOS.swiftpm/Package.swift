// swift-tools-version: 5.9

// StudyOS — a personal academic operating system for iPad.
//
// This is a Swift Playgrounds App package. Open the `StudyOS.swiftpm`
// folder directly in Swift Playgrounds on iPad; no Mac or Xcode is required.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "StudyOS",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "StudyOS",
            targets: ["AppModule"],
            bundleIdentifier: "com.kingmcclavin.StudyOS",
            teamIdentifier: "",
            displayVersion: "0.1",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .calendar),
            accentColor: .presetColor(.indigo),
            supportedDeviceFamilies: [
                .pad
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
