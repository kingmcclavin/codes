// swift-tools-version: 5.9
import PackageDescription

// NoScroll for iPhone, packaged as a Swift package.
//
// Extracted from https://github.com/Blueturboguy07/noscroll (ios/). SwiftPM
// cannot produce an installable .app with app extensions on its own, so the
// code lives here as libraries and `App/` holds the thin Xcode host (the
// `@main` entry points, Info.plists, entitlements and app icon).
//
//   NoScrollCore     platform-independent logic: schedule maths, life-in-weeks,
//                    SVG path parsing. Unit-tested.
//   NoScrollKit      the whole app UI, WKWebView wrapper, signed rule bundles,
//                    and the bundled engine (Resources/noscroll.js).
//   NoScrollWidgets  the home-screen shortcuts widget (WidgetKit).
//   NoScrollShield   the three Screen Time extensions (need Apple's gated
//                    Family Controls entitlement to run).
let package = Package(
    name: "NoScroll",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "NoScrollCore", targets: ["NoScrollCore"]),
        .library(name: "NoScrollKit", targets: ["NoScrollKit"]),
        .library(name: "NoScrollWidgets", targets: ["NoScrollWidgets"]),
        .library(name: "NoScrollShield", targets: ["NoScrollShield"]),
    ],
    targets: [
        .target(name: "NoScrollCore"),
        .target(
            name: "NoScrollKit",
            dependencies: ["NoScrollCore"],
            resources: [
                .copy("Resources/noscroll.js"),
                .copy("Resources/rules-signing.pub.raw"),
                .copy("Resources/Rules"),
            ]
        ),
        .target(name: "NoScrollWidgets"),
        .target(name: "NoScrollShield"),
        .testTarget(name: "NoScrollCoreTests", dependencies: ["NoScrollCore"]),
    ]
)
