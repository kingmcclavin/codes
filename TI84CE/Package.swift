// swift-tools-version: 5.9
//
// Development package for building and testing the emulator core on macOS or Linux.
// The iPad / iPhone app itself is TI84CE.swiftpm (open it in Swift Playgrounds or
// Xcode); it compiles the very same EmulatorCore sources.

import PackageDescription

let package = Package(
    name: "TI84CEDev",
    products: [
        .library(name: "EmulatorCore", targets: ["EmulatorCore"]),
        .executable(name: "ce-headless", targets: ["ce-headless"]),
    ],
    targets: [
        .target(
            name: "EmulatorCore",
            path: "TI84CE.swiftpm/EmulatorCore"
        ),
        .executableTarget(
            name: "ce-headless",
            dependencies: ["EmulatorCore"],
            path: "Tools/ce-headless"
        ),
        .executableTarget(
            name: "ce-dis",
            dependencies: ["EmulatorCore"],
            path: "Tools/ce-dis"
        ),
        .testTarget(
            name: "EmulatorCoreTests",
            dependencies: ["EmulatorCore"],
            path: "Tests/EmulatorCoreTests"
        ),
    ]
)
