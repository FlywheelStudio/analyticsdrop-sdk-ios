# Delivery reliability & consent

Covers the event pipeline from `emit` to ingest, the durable retry spool, and the runtime opt-out.
Shipped 2026-08-04 in 0.2.0 (issues [#1](https://github.com/FlywheelStudio/analyticsdrop-sdk-ios/issues/1)–[#4](https://github.com/FlywheelStudio/analyticsdrop-sdk-ios/issues/4)).

## What it does

- Buffers events, persists them, uploads them in batches, and **keeps** the ones that failed for a
  transient reason until they land — instead of dropping them after ~3s of retries.
- Stores that data where iOS won't purge it, and where iCloud won't back it up.
- Lets the host app turn collection off and on at runtime (consent toggle, kill switch), with the
  choice surviving relaunch.

## How it works

### Data flow

```
capture / track / identify
        └─> Core.emit          (serial queue "dev.analyticsdrop.core")
              ├─> EventQueue.append   → in-memory line + Application Support/AnalyticsDrop/events.jsonl
              └─> flushNow when count >= flushThreshold (20)
                    ├─ also on the 30s timer, on background, and at start()
                    ├─ lines = takeSpooledLines() + drainLines()
                    └─> APIClient.uploadLines
                          ├─ 2xx                       → done
                          ├─ 4xx (not 408/429)         → dropped, backend will never accept it
                          └─ network / 5xx / 408 / 429 → retry 1s, 2s, then EventQueue.spool(lines)
                                                          → retry.jsonl, re-sent next flush / next launch
```

At `start()` (and at `setEnabled(true)`), `Core.activate()` drains both files: `events.jsonl` holds
whatever the previous run buffered but never flushed (crash recovery), `retry.jsonl` holds
previously failed batches. Both go out as one batch; if that fails, they land back in the spool.

### Key files

| File | Role |
| --- | --- |
| `Sources/AnalyticsDrop/Internal/Core.swift` | Orchestration, session lifecycle, flush, enabled-flag gating |
| `Sources/AnalyticsDrop/Internal/EventQueue.swift` | Encoded-line buffer, live file, retry spool, caps |
| `Sources/AnalyticsDrop/Internal/APIClient.swift` | Gzip upload, in-flight retries, `UploadResult` classification |
| `Sources/AnalyticsDrop/Internal/OptOutStore.swift` | Persisted enable flag (`UserDefaults`) |

### Storage

`Application Support/AnalyticsDrop/` — created on `EventQueue` init, `isExcludedFromBackup = true`.

- `events.jsonl` — mirror of the in-memory buffer; truncated on every drain.
- `retry.jsonl` — failed batches. Capped at 512 KB (oldest evicted first) and 7 days; every line is
  JSON-validated on read so a crash-truncated line can't fail the whole batch.

Both are JSON-lines of already-encoded `WireEvent`s, concatenated into `{"batch":[…]}` at upload
time — events are encoded exactly once.

### Consent

`AnalyticsDrop.setEnabled(false)` → cancel timer, end session, `EventQueue.discardAll()` (memory +
both files), release identity/queue/transport. `setEnabled(true)` → activate, install swizzle if
needed, begin a fresh session. `AnalyticsDrop.isEnabled` reads the persisted flag; absence means
enabled.

## External services

Ingest backend only: `POST {endpoint}/v1/events`, header `X-AnalyticsDrop-Key`, gzip body
(plain JSON if compression fails). `endpoint` is a required argument — see
[decision 001](../decisions/001-endpoint-is-required.md).

## Testing

`swift test` (macOS build; UIKit capture is compiled out there, so also
`xcodebuild -scheme AnalyticsDrop -destination 'generic/platform=iOS' build`).

- `Tests/…/DeliveryTests.swift` — `APIClient.classify` across 2xx/4xx/5xx/408/429/network;
  `OptOutStore` default-enabled, persistence, opt-back-in.
- `Tests/…/GzipQueueTests.swift` — crash recovery, drain, storage location and backup exclusion,
  spool accumulation, byte-cap eviction order, age cap, malformed-line skipping, `discardAll`,
  timestamp round-trip.

## Gotchas

- **Duplicates are possible.** A batch accepted by ingest whose response never arrived is retried;
  ingest dedupes on `eventId`.
- **`UserDefaults.bool(forKey:)` is `false` when unset** — reading the enable flag naively would
  disable the SDK for everyone who never calls `setEnabled`. `OptOutStore` checks for key absence
  explicitly (pinned by `testDefaultsToEnabledWhenNeverSet`).
- **The age cap depends on matching ISO8601 options.** `EventLine.timestamp` must parse what
  `ISO8601.string(from:)` writes (`.withFractionalSeconds`), or the cap silently no-ops
  (`testTimestampRoundTripsWhatTheEncoderWrites`).
- **The swizzle is never uninstalled** on `setEnabled(false)`; capture callbacks still fire and
  return without emitting. Not calling `start()` remains the strongest off-switch.
- **`swift test` doesn't compile the UIKit capture path** (`#if canImport(UIKit)` is false on
  macOS). A green `swift test` is not evidence that `UIKitCapture`/`ScreenFingerprint` compile.
