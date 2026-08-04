# 003 — Runtime opt-out: `setEnabled`, discard-not-hold, persisted

**Date:** 2026-08-04 · **Status:** accepted · **Issue:** [#4](https://github.com/FlywheelStudio/analyticsdrop-sdk-ios/issues/4)

## Context

Collection could only be prevented by never calling `start()`. That is a genuinely complete
off-switch — no swizzle, no session, no queue — and integrators rely on it to keep Debug, Simulator,
ad-hoc, and TestFlight builds out of production data. But the decision had to be made at launch,
before any UI exists, which rules out a "share usage data" settings toggle, a consent prompt
answered on first run, and a server-side kill switch.

## Decision

Add `AnalyticsDrop.setEnabled(_:)` and `AnalyticsDrop.isEnabled`.

- **Disabling** cancels the flush timer, ends the session, and **discards** everything pending in
  memory *and* on disk. Holding the backlog would mean an opted-out user still ships their events at
  the next flush, which defeats the point.
- **Enabling** builds the machinery, installs the swizzle if needed, and begins a fresh session — no
  relaunch required in either direction.
- **The choice is persisted** (`UserDefaults`, key `dev.analyticsdrop.collectionEnabled`). A consent
  decision that evaporates on next launch isn't a consent decision. `start()` on a later run sees
  the opt-out *before* creating the queue or installing the swizzle, so an opted-out install behaves
  like one that never called `start()`.
- **Absence means enabled.** `UserDefaults.bool(forKey:)` returns `false` for an unset key; read
  naively that would disable the SDK for every existing integrator. `OptOutStore` checks
  `object(forKey:) == nil` explicitly, and a test pins it.
- Every emit path (`identify`, `track`, `setScreenName`, `captureScreen`, session lifecycle) guards
  on the flag — not just screen capture.

## Alternatives considered

- **`startDeferred()` / `resume()`** — installs the swizzle at launch and waits for consent. Same
  end state, but it adds a second lifecycle shape to document and doesn't cover the mid-session kill
  switch as naturally.
- **In-memory only, no persistence** — smaller, but silently resumes collecting after a relaunch for
  a user who opted out. Wrong default for a consent control.

## Consequences

- The swizzle, once installed, is not removed on disable (uninstalling a method swizzle at runtime
  is not safe when other code may have swizzled on top). Capture callbacks still fire; they return
  immediately without emitting. Documented, and the reason `start()` gating remains the stronger
  off-switch.
- Opting out then back in produces a new `sessionId` — correct, since the events either side are not
  one continuous session.
