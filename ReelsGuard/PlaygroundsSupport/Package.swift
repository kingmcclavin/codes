// swift-tools-version: 5.8

// Swift Playgrounds app (iPad or Mac). Generated layout — see
// scripts/build-playgrounds-app.py. Open the ReelsGuard.swiftpm folder in
// Swift Playgrounds and tap Run.

import AppleProductTypes
import PackageDescription

let package = Package(
    name: "Reels Guard",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Reels Guard",
            targets: ["AppModule"],
            bundleIdentifier: "com.example.reelsguard",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .leaf),
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
            ],
            appCategory: .productivity
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
