import Foundation

/// Immutable SDK configuration. Constructed by `Wayfind.start`.
struct WayfindConfig {
    let apiKey: String
    let endpoint: URL
    let debug: Bool

    /// Flush when this many events are buffered.
    var flushThreshold = 20
    /// Flush at least this often (seconds).
    var flushInterval: TimeInterval = 30
    /// Grace period before a backgrounded session ends (handles quick app switches).
    var sessionGrace: TimeInterval = 30
    /// Emit redacted thumbnails on first sighting. Off for the POC first demo (see spec §10 fallback).
    var captureThumbnails = false
    /// Ignore a repeated identical fingerprint seen within this window (container re-layout).
    var debounceInterval: TimeInterval = 0.3

    /// Placeholder hosted endpoint; dev/POC passes an explicit local URL to `Wayfind.start`.
    static let defaultEndpoint = URL(string: "https://ingest.wayfind.dev")!
}
