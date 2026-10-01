// swift-tools-version:5.9
import PackageDescription

// Platform-independent policy logic shared by the app, the Safari web
// extension handler and the share extension. Depends on Foundation only, so it
// can be unit-tested with `swift test` on macOS or Linux.
let package = Package(
    name: "ReelsGuardCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ReelsGuardCore", targets: ["ReelsGuardCore"]),
    ],
    targets: [
        .target(name: "ReelsGuardCore"),
        .testTarget(name: "ReelsGuardCoreTests", dependencies: ["ReelsGuardCore"]),
    ]
)
