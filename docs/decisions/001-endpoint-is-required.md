# 001 — `endpoint` is a required argument of `start()`

**Date:** 2026-08-04 · **Status:** accepted · **Issue:** [#2](https://github.com/FlywheelStudio/analyticsdrop-sdk-ios/issues/2)

## Context

`AnalyticsDrop.start(apiKey:endpoint:debug:)` took `endpoint: URL? = nil` and fell back to
`AnalyticsDropConfig.defaultEndpoint = https://ingest.analyticsdrop.dev`. That host does not
resolve — the backend's own GO-LIVE checklist lists "make the SDK's default endpoint actually
resolve" as an open item.

So the one-argument call the signature invites — `AnalyticsDrop.start(apiKey: "ad_live_…")` —
compiled, installed the swizzle, recorded sessions, and posted every batch nowhere. With
`debug: false` (the production default) there was no console output either: a silent total data
loss that looked like a healthy integration.

## Decision

Remove `defaultEndpoint` and make `endpoint: URL` required.

## Alternatives considered

- **Point the default at the real production ingest host** — the reporter's first preference, and
  the right answer once one exists. It doesn't: the domain is unprovisioned. Inventing a hostname
  would recreate the same bug with a different string.
- **Keep the default, log unconditionally on first flush when it's in use** — a `print` in a
  release build is the wrong channel, and it fails quietly for anyone not watching a console.
  Considered as a stopgap only if a required argument had been unacceptable.

## Consequences

- Source-breaking for anyone who omitted `endpoint` — deliberately: a compile error is the loudest
  possible version of this bug, and it can only fire on integrations that were already broken.
  Version bumped to 0.2.0; `Examples/DemoHarness` and the README updated.
- When the hosted ingest domain ships, a *correct* default can be reintroduced additively
  (an overload), superseding this record.
- The sibling SDKs (`SDK/core`, `SDK/flutter`) still carry the same placeholder default. Out of
  scope for this repo; worth filing there.
