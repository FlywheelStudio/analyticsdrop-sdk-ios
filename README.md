# AnalyticsDrop iOS SDK

One-line screen-journey analytics for iOS (UIKit **and** SwiftUI). Zero third-party dependencies.

```swift
import AnalyticsDrop

// App launch (AppDelegate / App init):
AnalyticsDrop.start(apiKey: "ad_test_…", endpoint: URL(string: "http://localhost:3100"), debug: true)

// SwiftUI root:
WindowGroup { ContentView().analyticsDropTracked() }

// Optional:
AnalyticsDrop.identify("cust_123")
AnalyticsDrop.track("purchase", properties: ["value": 9.99])
SomeView().analyticsDropScreen("Checkout")   // exact name escape hatch
```

## How it works

- **UIKit** — swizzles `UIViewController.viewDidAppear`; leaf content controllers become screens
  named by their class (`CheckoutViewController`). Container/system controllers are filtered.
- **SwiftUI** — the same swizzle fires for the `UIHostingController`s that back `NavigationStack`
  pushes, sheets, and `TabView` switches. Since the hosting class name is useless, the SDK computes
  a **structural fingerprint** of the view hierarchy (Mechanism C) as the screen id.
- **Privacy invariant** — fingerprints record only structure (`depth, class, bucketed frame,
  hasText`); never text content. Thumbnails (redacted boxes) are a later addition.

Events batch and upload to `POST {endpoint}/v1/events` with header `X-AnalyticsDrop-Key`.

## Status (POC)

Requires iOS 15+, swift-tools 5.9. Transport, session/seq, identity, queue, UIKit + SwiftUI
capture are implemented. Deferred to the next milestone: redacted thumbnails, richer
`NavigationStack` observation (Mechanism A), and the full XCUITest capture-rate harness.

This package is developed here and will be published to its own GitHub repository; consumers add it
via Swift Package Manager.
