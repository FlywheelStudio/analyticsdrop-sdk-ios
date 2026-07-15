# DemoHarness

A tiny SwiftUI app that links the local AnalyticsDrop SDK and **auto-drives** a navigation journey
(Home → Detail → Paywall → Checkout → purchase) so screen-view capture can be verified end-to-end
with no manual tapping. This is the harness used to validate the SDK against the backend.

## Run

```bash
# 1) Start a backend that accepts POST /v1/events (either the Next app, or the standalone
#    ingest-server in the analyticsdrop backend repo: `npx tsx scripts/ingest-server.ts`).
# 2) Build & run the harness on a simulator:
xcodegen generate
xcodebuild -project AnalyticsDropDemo.xcodeproj -scheme AnalyticsDropDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./dd \
  CODE_SIGNING_ALLOWED=NO build
xcrun simctl install booted ./dd/Build/Products/Debug-iphonesimulator/AnalyticsDropDemo.app
xcrun simctl launch booted dev.analyticsdrop.demo
```

Events appear in the dashboard under the app whose key is set in `Sources/App.swift`
(`ad_test_primus_dev` → endpoint `http://localhost:3100`).
