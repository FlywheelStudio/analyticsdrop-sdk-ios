# AnalyticsDrop iOS SDK

One-line screen-journey analytics for iOS (UIKit **and** SwiftUI). Zero third-party dependencies.

```swift
import AnalyticsDrop

// App launch (AppDelegate / App init). This one call is what enables capture.
AnalyticsDrop.start(apiKey: "ad_test_…", endpoint: URL(string: "http://localhost:3100")!, debug: true)

// SwiftUI root — forward-compatible marker, NOT the thing that turns capture on (see below):
WindowGroup { ContentView().analyticsDropTracked() }

// Optional:
AnalyticsDrop.identify("cust_123")
AnalyticsDrop.track("purchase", properties: ["value": 9.99])
SomeView().analyticsDropScreen("Checkout")   // exact name escape hatch
AnalyticsDrop.setEnabled(false)              // runtime opt-out (consent toggle / kill switch)
```

`endpoint` is **required** — point it at your ingest host (`https://…`) or a local backend in dev.
There is deliberately no default: the previous placeholder default meant an omitted argument sent
every batch to a host that doesn't exist, with no error and (outside `debug`) no log.

> **`.analyticsDropTracked()` is a no-op in 0.2.x.** Capture comes entirely from `start()`, which
> installs a global `UIViewController.viewDidAppear` swizzle. The modifier neither enables capture
> (omit `start()` and you get nothing) nor scopes it (apply it to a subtree and you still capture
> the whole app). It's kept as the stable integration point for richer navigation observation
> (Mechanism A). DEBUG builds log once if the modifier is used without `start()`.

## How it works

- **UIKit** — swizzles `UIViewController.viewDidAppear`; leaf content controllers become screens
  named by their class (`CheckoutViewController`). Container/system controllers are filtered.
- **SwiftUI** — the same swizzle fires for the `UIHostingController`s that back `NavigationStack`
  pushes, sheets, and `TabView` switches. Since the hosting class name is useless, the SDK computes
  a **structural fingerprint** of the view hierarchy (Mechanism C) as the screen id.
- **Privacy invariant** — fingerprints record only structure (`depth, class, bucketed frame,
  hasText`); never text content. Thumbnails (redacted boxes) are a later addition.

Events batch and upload to `POST {endpoint}/v1/events` with header `X-AnalyticsDrop-Key`.

## Delivery & retention

Events are buffered in memory and mirrored to JSON-lines files in
`Application Support/AnalyticsDrop` (excluded from iCloud backup — not `Caches`, which iOS purges
under storage pressure). A batch is uploaded on the flush interval, at the flush threshold, and on
background.

Failures are classified: **4xx** (bad key, malformed batch) drops the batch, since resending the
same bytes changes nothing; **network errors, 5xx, 408, 429** retry twice in-flight (1s, 2s) and are
then spooled to disk and re-sent on the next flush cycle and the next launch. The spool is bounded
at 512 KB (oldest dropped first) and 7 days.

## Consent & opt-out

`AnalyticsDrop.setEnabled(false)` stops emission, discards everything pending (memory *and* disk —
an opted-out user never ships their backlog), and ends the session; `setEnabled(true)` resumes with
a fresh session. The choice persists across launches, and `AnalyticsDrop.isEnabled` reads it back.

Not calling `start()` is still the strongest off-switch — no swizzle, no session, no queue. Prefer
it when the decision can be made at launch (e.g. gating Debug/TestFlight builds out of prod data).

## Status (POC)

Requires iOS 15+, swift-tools 5.9. Transport, session/seq, identity, durable queue with retry,
runtime opt-out, UIKit + SwiftUI capture are implemented. Deferred to the next milestone: redacted
thumbnails, richer `NavigationStack` observation (Mechanism A), and the full XCUITest capture-rate
harness.

## Install (Swift Package Manager)

In Xcode: **File → Add Package Dependencies…** and paste:

```
https://github.com/FlywheelStudio/analyticsdrop-sdk-ios
```

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/FlywheelStudio/analyticsdrop-sdk-ios", from: "0.1.0")
]
```

## License

MIT — see [LICENSE](./LICENSE).

---

AnalyticsDrop is a product of [Flywheel Studio](https://flywheel.so).
