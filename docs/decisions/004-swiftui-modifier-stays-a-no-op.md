# 004 — `.analyticsDropTracked()` stays a no-op, but stops pretending otherwise

**Date:** 2026-08-04 · **Status:** accepted · **Issue:** [#1](https://github.com/FlywheelStudio/analyticsdrop-sdk-ios/issues/1)

## Context

`analyticsDropTracked()` is `func analyticsDropTracked() -> some View { self }`. The doc comment
said so; the README presented it as *the* SwiftUI integration step with no caveat. A SwiftUI adopter
reasonably concludes the modifier is what enables capture. It isn't — capture is the global
`UIViewController.viewDidAppear` swizzle installed by `start()`. Two failure modes, neither of which
surfaces as an error:

1. Omit (or gate) `start()`, expect capture anyway because "I added the modifier" → no data.
2. Apply the modifier to a subtree expecting scoped capture → the whole app is captured.

## Decision

Keep it a no-op, and make that impossible to miss:

- README carries an explicit callout: the modifier neither enables nor scopes capture in 0.2.x.
- The doc comment leads with what it does *not* do, in those two specific failure modes' terms.
- DEBUG builds log once, from `onAppear`, when the modifier is applied but `start()` was never
  called — a combination that is always a mistake. Release builds are untouched.
- `Core.startCalled` is set **synchronously** at the top of `AnalyticsDrop.start` (behind an
  `NSLock`), because `Core.start` finishes its work on a serial queue and a check from `onAppear`
  would otherwise race and warn spuriously.

## Alternatives considered

- **Make it real (Mechanism A)** — the modifier installs/scopes capture via `NavigationStack`
  observation. Still the intended destination, still the deferred milestone; it is a redesign of the
  SwiftUI capture path, not a bug fix, and shipping it under a patch would change capture semantics
  for existing integrations mid-flight.
- **Delete the modifier** — honest, but breaks every SwiftUI integration and throws away the API
  slot Mechanism A wants.

## Consequences

- The API surface keeps a member that does nothing at runtime; the warning is the guard against that
  being misread.
- When Mechanism A lands, the modifier gains behaviour without a source break, and this record gets a
  superseding one.
