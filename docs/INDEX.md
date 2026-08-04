# Docs Index — AnalyticsDrop iOS SDK

Entry point for all documentation in this repo. Update in the same commit as any doc change.

| Doc | What's in it |
| --- | --- |
| [STATE.md](STATE.md) | Living status board: in progress, completed, backlog |
| [features/delivery-and-consent.md](features/delivery-and-consent.md) | Durable queue, retry spool, storage location, runtime opt-out |
| [decisions/001-endpoint-is-required.md](decisions/001-endpoint-is-required.md) | Why `endpoint` lost its default (breaking, 0.2.0) |
| [decisions/002-retry-spool-and-storage.md](decisions/002-retry-spool-and-storage.md) | Keep retriable failures on disk; Application Support over Caches |
| [decisions/003-runtime-opt-out.md](decisions/003-runtime-opt-out.md) | `setEnabled` semantics: discard-not-hold, persisted choice |
| [decisions/004-swiftui-modifier-stays-a-no-op.md](decisions/004-swiftui-modifier-stays-a-no-op.md) | Why `.analyticsDropTracked()` isn't made "real" yet |

Product/API overview lives in the repo [README](../README.md).
