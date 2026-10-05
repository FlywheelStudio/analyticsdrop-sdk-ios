# STATE — AnalyticsDrop iOS SDK

_Last updated: 2026-10-05_

## In Progress

_Nothing._

## Completed

| Feature | Shipped | Doc |
| --- | --- | --- |
| Core SDK: transport, session/seq, identity, UIKit + SwiftUI capture | 0.1.0 | [README](../README.md) |
| Gzip transport, privacy manifest, screen-name hints | 0.1.0 | [README](../README.md) |
| Delivery reliability & consent (issues #1–#4) | 0.2.0 — 2026-08-04 | [features/delivery-and-consent.md](features/delivery-and-consent.md) |
| `reset()` for logout / account deletion | 2026-10-05 (unreleased, `feature/sdk-reset`) | [features/identity-reset.md](features/identity-reset.md) |

0.2.0 is source-breaking: `AnalyticsDrop.start` now requires `endpoint`
([decision 001](decisions/001-endpoint-is-required.md)).

## Backlog

- **Mechanism A** — real `NavigationStack` observation behind `.analyticsDropTracked()`, which would
  let the modifier enable and scope capture instead of being a no-op
  ([decision 004](decisions/004-swiftui-modifier-stays-a-no-op.md)).
- **Hosted ingest default** — once `ingest.analyticsdrop.dev` (or its replacement) is provisioned,
  reintroduce a correct default endpoint additively, superseding decision 001. Tracked in the
  backend repo's GO-LIVE checklist.
- **Same placeholder-endpoint footgun in the sibling SDKs** (`SDK/core`, `SDK/flutter` in the
  `analyticsdrop` repo) — file there.
- Redacted thumbnails; XCUITest capture-rate harness.
- CI: run `swift test` **and** an iOS-destination `xcodebuild` build, since the macOS test build
  compiles neither `UIKitCapture` nor `ScreenFingerprint`.
