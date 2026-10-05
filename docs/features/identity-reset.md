# Identity reset (logout / account deletion)

Shipped on `feature/sdk-reset` (2026-10-05). Decision: [005](../decisions/005-reset-identity.md).

## What it does

`AnalyticsDrop.reset()` ends the current identity: it closes the session, forgets the `identify`
user ID, and rotates the anonymous device ID. The next person on the device starts clean.

## How it works

| Step | Where |
| --- | --- |
| Public entry point | `Sources/AnalyticsDrop/AnalyticsDrop.swift` — `reset()` |
| Session hand-off on the serial queue | `Sources/AnalyticsDrop/Internal/Core.swift` — `Core.reset()` |
| Clear user ID, rotate + persist id | `Sources/AnalyticsDrop/Internal/IdentityManager.swift` — `reset()`, `rotatePersistedId` |

Order on the serial queue: `session_end` (old ids) → clear user ID → new Keychain id → reset the
screen debounce → `session_start` (new ids) if foregrounded. Calls before or after `reset()` keep
their order because every public call goes through the same queue.

With no live identity (not started, or opted out), `Core.reset()` calls
`IdentityManager.rotatePersistedId` directly.

## Data model

No wire change. The new identity is just a new `anonymousId` and no `userId`. The backend creates a
new user row on first sight.

## Integration

```swift
func signOut() {
    try? auth.signOut()
    AnalyticsDrop.reset()
}

func deleteAccount() async throws {
    try await auth.deleteAccount()   // reset only after the delete succeeds
    AnalyticsDrop.reset()
}
```

## Testing

`Tests/AnalyticsDropTests/ResetTests.swift`:

- Keychain rotation persists across a fresh `IdentityManager` (guards the duplicate-item bug).
- `Core` end to end: `session_end` carries the old ids and user ID; the following events carry the
  new `anonymousId`, a new `sessionId`, `seq` restarting, and no `userId`.
- Opted out: nothing emitted, persisted id rotated.
- Before `start()`: the id rotates, and the next `start()` uses it.

Tests use a unique Keychain service and temp queue directory, so they never touch real state.

## Gotchas

- Queued and spooled events of the old identity still upload after `reset()`. A backend erasure that
  runs before they land will see them arrive later.
- `reset()` deletes nothing server-side.
- The macOS `swift test` build does not compile the UIKit capture path; build for an iOS
  destination too.
