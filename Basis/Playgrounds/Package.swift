// swift-tools-version: 5.9

// Swift Playgrounds (iPad) app package. `scripts/make-swiftpm.sh` copies the
// app sources next to this manifest to produce Basis.swiftpm.

import AppleProductTypes
import PackageDescription

let package = Package(
    name: "Basis",
    platforms: [
        .iOS("17.0"),
    ],
    products: [
        .iOSApplication(
            name: "Basis",
            targets: ["AppModule"],
            bundleIdentifier: "com.example.inkpad.playgrounds",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .asset("AppIcon"),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [
                .pad,
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad])),
            ]
        ),
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        ),
    ]
)
