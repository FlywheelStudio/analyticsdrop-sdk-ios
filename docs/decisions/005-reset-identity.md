# 005 — `reset()`: forget the user, rotate the anonymous id

**Date:** 2026-10-05 · **Status:** accepted

## Context

The SDK had `identify()` but no way to undo it. Two defects followed:

- `externalUserId` stayed in memory until relaunch, so events after a logout still carried the old
  user ID.
- `anonymousId` lives in the Keychain and survives reinstall. When a second person signs in on the
  same device, the backend's identity stitching sees a known `anonymousId` with a new
  `external_user_id` and overwrites the user row. The first person's whole history becomes the
  second person's.

Account deletion makes this sharper: the deleted user's device identity would carry into the next
account.

## Decision

Add `AnalyticsDrop.reset()`. On Core's serial queue it:

1. Emits `session_end` under the **old** identity (if a session is open).
2. Clears `externalUserId` and writes a fresh UUID to the Keychain as the new `anonymousId`.
3. Opens a new session at once if the app is in the foreground; otherwise the next foreground does.

Events already queued keep the identity they were emitted under and upload normally — they belong
to the old user.

**No live identity** (before `start()`, or opted out per decision 003): `reset()` still rotates the
persisted Keychain id and emits nothing. The next `start()` or `setEnabled(true)` reads the new id,
so a reset is never lost to timing.

The Keychain write is now update-or-add (`SecItemUpdate`, then `SecItemAdd` on
`errSecItemNotFound`). A bare `SecItemAdd` over an existing item fails with `errSecDuplicateItem`.

## Alternatives considered

- **Clear the user ID only, keep the `anonymousId`.** Fixes the in-memory leak but not the
  cross-account merge — the server keys stitching on `anonymousId`.
- **Flush immediately inside `reset()`.** Shrinks the window in which old-identity events can
  arrive after a backend erasure. Dropped: it does not close the window (an upload can still fail
  and spool), and it made the session hand-off untestable without a network stub. The backend must
  handle late events either way.
- **Discard queued events on reset.** Correct for deletion, wrong for logout (those events are
  real). The host app can call `setEnabled(false)` first if it wants the discard.

## Consequences

- Host apps must call `reset()` on logout and after a successful account deletion. Primus does.
- Queued or spooled events of a deleted user can reach the backend after it erases that user
  (normal flush ≤ 30 s; spool up to 7 days). Server-side erasure must tolerate this.
- `Core` gained an internal init that injects the opt-out store, Keychain service and queue
  directory, so tests drive the real session hand-off without touching the host's identity.
