import Foundation

/// The entire public surface of the AnalyticsDrop SDK.
///
/// Integrate in one line at app launch:
/// ```swift
/// AnalyticsDrop.start(apiKey: "ad_test_…", endpoint: URL(string: "https://your-ingest-host")!)
/// ```
///
/// Screen capture comes from `start()` alone (it installs the `viewDidAppear` swizzle). The
/// SwiftUI `.analyticsDropTracked()` modifier is a forward-compatible no-op in 0.2.x.
public enum AnalyticsDrop {
    /// Call once, as early as possible (App init / AppDelegate).
    /// - Parameters:
    ///   - apiKey: Your app's ingest key (`X-AnalyticsDrop-Key`).
    ///   - endpoint: Base URL of your ingest backend, e.g. `https://ingest.example.com` or
    ///     `http://localhost:3100` in dev. Required: there is no hosted default yet, and a
    ///     placeholder default meant an omitted argument silently sent every batch nowhere (#2).
    ///   - debug: When true, logs SDK activity to the console.
    public static func start(apiKey: String, endpoint: URL, debug: Bool = false) {
        Core.startCalled = true
        Core.shared.start(
            config: AnalyticsDropConfig(apiKey: apiKey, endpoint: endpoint, debug: debug)
        )
    }

    /// Turn collection on or off at runtime — for a "share usage data" settings toggle, a consent
    /// prompt answered after launch, or a server-side kill switch.
    ///
    /// Disabling stops all emission, discards everything pending (in memory and on disk — an
    /// opted-out user must not ship their backlog later), and ends the session. Enabling starts a
    /// fresh session; no relaunch needed either way. The choice is persisted, so later launches
    /// honour it before any event is recorded.
    ///
    /// Note: *not calling* `start()` remains the strongest form of off — no swizzle is installed
    /// and no queue exists. Prefer it when the decision can be made at launch (build gating).
    public static func setEnabled(_ enabled: Bool) {
        Core.shared.setEnabled(enabled)
    }

    /// Whether collection is currently enabled. `true` unless `setEnabled(false)` was called
    /// (on this run or a previous one).
    public static var isEnabled: Bool { OptOutStore.shared.isEnabled }

    /// Link the customer's own user ID. Triggers identity stitching server-side.
    public static func identify(_ userId: String) {
        Core.shared.identify(userId)
    }

    /// Forget the current user and start a new anonymous identity. Call it when the user logs out,
    /// and after an account deletion succeeds.
    ///
    /// Ends the current session under the old identity, clears the `identify` user ID, and rotates
    /// the anonymous device ID (persisted, so it survives relaunch). Without it, the next account
    /// on the same device shares the old anonymous ID, and server-side identity stitching merges
    /// the two users' histories. Events already queued keep the identity they were recorded
    /// under and still upload. A new session starts at once if the app is in the foreground.
    ///
    /// Safe to call before `start()` or while collection is disabled: it rotates the persisted ID
    /// and emits nothing.
    public static func reset() {
        Core.shared.reset()
    }

    /// Manual conversion event. Deliberately minimal.
    public static func track(_ event: String, properties: [String: AnalyticsDropValue]? = nil) {
        Core.shared.track(event, properties: properties)
    }

    /// Override the auto-detected screen name for the current screen (emits a `manual` screen view).
    public static func setScreenName(_ name: String) {
        Core.shared.setScreenName(name)
    }
}

/// A JSON-scalar value usable in `track` properties.
public enum AnalyticsDropValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else {
            self = .string(try c.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        }
    }
}

extension AnalyticsDropValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}
extension AnalyticsDropValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
}
extension AnalyticsDropValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .number(value) }
}
extension AnalyticsDropValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}
