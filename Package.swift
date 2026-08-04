// swift-tools-version:5.9
import PackageDescription

// swift-tools 5.9 keeps the default language mode at 5, so the Swift 6 compiler treats data-race
// concerns as warnings (not errors) for this swizzling + off-main-thread SDK. See DECISIONS.
let package = Package(
    name: "AnalyticsDrop",
    // iOS is the shipping platform; the macOS floor only exists so `swift test` builds the
    // SwiftUI extensions locally (UIKit capture is `#if canImport(UIKit)`-gated out there).
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "AnalyticsDrop", targets: ["AnalyticsDrop"]),
    ],
    targets: [
        .target(
            name: "AnalyticsDrop",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(name: "AnalyticsDropTests", dependencies: ["AnalyticsDrop"]),
    ]
)
