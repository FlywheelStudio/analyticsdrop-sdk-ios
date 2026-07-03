// swift-tools-version:5.9
import PackageDescription

// swift-tools 5.9 keeps the default language mode at 5, so the Swift 6 compiler treats data-race
// concerns as warnings (not errors) for this swizzling + off-main-thread SDK. See DECISIONS.
let package = Package(
    name: "Wayfind",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "Wayfind", targets: ["Wayfind"]),
    ],
    targets: [
        .target(name: "Wayfind"),
        .testTarget(name: "WayfindTests", dependencies: ["Wayfind"]),
    ]
)
