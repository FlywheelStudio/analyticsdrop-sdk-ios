# 002 — Retriable failures are spooled to disk; storage moves to Application Support

**Date:** 2026-08-04 · **Status:** accepted · **Issue:** [#3](https://github.com/FlywheelStudio/analyticsdrop-sdk-ios/issues/3)

## Context

Two POC shortcuts combined into silent, *biased* data loss:

1. `APIClient` retried twice (1s, 2s) and then dropped the batch. A user on a bad connection, or an
   app opened during a brief ingest outage, lost those events permanently after ~3s. The loss
   correlates with poor connectivity, so funnel drop-off is over-reported for exactly the users
   having the worst experience.
2. The JSON-lines file lived in `Caches/` (fallback `temporaryDirectory`), both of which iOS purges
   under storage pressure — so crash recovery could come up empty precisely on the devices that
   needed it.

## Decision

- **Classify failures.** `UploadResult`: `success` (2xx), `permanent` (4xx except 408/429 — bad key
  or malformed batch, resending changes nothing), `retriable` (network error, 5xx, 408, 429).
- **Keep retriable failures.** After the two in-flight retries, the encoded lines are spooled to
  `retry.jsonl` and re-sent on the next flush cycle and at the next launch. Bounded at **512 KB**
  (oldest evicted first) and **7 days**, so it cannot grow without limit or resurrect stale events.
- **Move storage to `Application Support/AnalyticsDrop`**, created on init and marked
  `isExcludedFromBackup` (survives storage pressure without polluting iCloud backups).
- **Validate every line on read.** A crash mid-append can truncate the last line; unparseable lines
  are dropped, because one bad line would turn the whole concatenated `{"batch":[…]}` into a 400 →
  `permanent` → the entire spool discarded.

## Alternatives considered

- **More in-flight retries / longer backoff** — keeps a `URLSession` task alive across an app the
  user may background, and still loses everything if the process dies. Disk is the durable answer.
- **Retry everything, including 4xx** — a wrong API key would then spool forever and re-POST a
  guaranteed rejection on every launch.
- **Single file for both live buffer and retry spool** — the live file mirrors the in-memory buffer
  and is truncated on drain; overloading it makes double-send easy to introduce. Two files keep the
  ownership rule trivial: the spool holds only lines nobody is currently trying to send.

## Consequences

- `EventQueue` now stores encoded lines rather than `WireEvent`s, and `Core` flushes via
  `uploadLines`. Events are encoded once, and the buffer can no longer diverge from the file.
- `EventQueue(directory:maxSpoolBytes:maxAge:)` is injectable, so tests use a temp directory instead
  of the developer's real Application Support.
- Duplicates are possible by design: a batch the backend accepted but whose response never arrived
  is retried. Ingest is expected to dedupe on `eventId`.
