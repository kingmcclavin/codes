// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TI84Emulator",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        // Platform-independent hardware emulation (CPU, memory, ASIC, LCD, ...).
        .library(name: "TI84EmulatorCore", targets: ["TI84EmulatorCore"]),
        // SwiftUI front end (calculator body, LCD renderer, keypad, debugger).
        .library(name: "TI84EmulatorUI", targets: ["TI84EmulatorUI"]),
        // Headless developer tool: boot a ROM, dump the LCD, run CPU test suites.
        .executable(name: "ti84-cli", targets: ["ti84-cli"]),
    ],
    targets: [
        .target(
            name: "TI84EmulatorCore",
            // The ROM image lives in Sources/TI84EmulatorCore/Resources/ti84rom.rom
            // and is loaded at runtime through Bundle.module. It is never compiled
            // into Swift source.
            resources: [.process("Resources")]
        ),
        .target(
            name: "TI84EmulatorUI",
            dependencies: ["TI84EmulatorCore"]
        ),
        .executableTarget(
            name: "ti84-cli",
            dependencies: ["TI84EmulatorCore"]
        ),
        .testTarget(
            name: "TI84EmulatorCoreTests",
            dependencies: ["TI84EmulatorCore"]
        ),
    ]
)
