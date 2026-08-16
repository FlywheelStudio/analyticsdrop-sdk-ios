import Foundation

/// Immutable SDK configuration. Constructed by `AnalyticsDrop.start`.
struct AnalyticsDropConfig {
    let apiKey: String
    let endpoint: URL
    let debug: Bool

    /// Flush when this many events are buffered.
    var flushThreshold = 20
    /// Flush at least this often (seconds).
    var flushInterval: TimeInterval = 30
    /// Grace period before a backgrounded session ends (handles quick app switches).
    var sessionGrace: TimeInterval = 30
    /// Emit a redacted wireframe thumbnail on the first sighting of each screen (D22): colored
    /// rounded rects + text bars only, never real pixels or text.
    var captureThumbnails = true
    /// Ignore a repeated identical fingerprint seen within this window (container re-layout).
    var debounceInterval: TimeInterval = 0.3

    // No `defaultEndpoint`: `endpoint` is a required argument of `AnalyticsDrop.start`. The old
    // placeholder default (`https://ingest.analyticsdrop.dev`, which does not resolve) turned an
    // omitted argument into silent total data loss that looked like a working integration (#2).
}
