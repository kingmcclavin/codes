// swift-tools-version: 5.9

// Swift Playgrounds / Xcode app package for the TI-84 Plus CE emulator.
// Open the TI84CE.swiftpm folder in Swift Playgrounds (iPad or Mac) or Xcode.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "TI84CE",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .iOSApplication(
            name: "TI-84 CE",
            targets: ["AppModule"],
            bundleIdentifier: "com.example.ti84ce-emulator",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .calculator),
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
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: ".",
            exclude: ["README.md"],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
