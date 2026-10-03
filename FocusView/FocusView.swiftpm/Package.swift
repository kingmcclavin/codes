// swift-tools-version: 5.8

// Swift Playgrounds app package. Swift Playgrounds may regenerate this file
// when you change App Settings (name, icon, colour) on the iPad.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "FocusView",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .iOSApplication(
            name: "FocusView",
            targets: ["AppModule"],
            bundleIdentifier: "com.focusview.app",
            teamIdentifier: "",
            displayVersion: "0.1",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .tv),
            accentColor: .presetColor(.indigo),
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
