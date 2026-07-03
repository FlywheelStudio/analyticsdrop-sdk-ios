import Foundation

/// The entire public surface of the Wayfind SDK.
///
/// Integrate in one line at app launch:
/// ```swift
/// Wayfind.start(apiKey: "wf_test_…")
/// ```
/// and (SwiftUI) attach `.wayfindTracked()` at the root.
public enum Wayfind {
    /// Call once, as early as possible (App init / AppDelegate).
    /// - Parameters:
    ///   - apiKey: Your app's ingest key (`X-Wayfind-Key`).
    ///   - endpoint: Base URL of the backend. Defaults to the hosted endpoint; pass a local URL for dev.
    ///   - debug: When true, logs SDK activity to the console.
    public static func start(apiKey: String, endpoint: URL? = nil, debug: Bool = false) {
        Core.shared.start(
            config: WayfindConfig(apiKey: apiKey, endpoint: endpoint ?? WayfindConfig.defaultEndpoint, debug: debug)
        )
    }

    /// Link the customer's own user ID. Triggers identity stitching server-side.
    public static func identify(_ userId: String) {
        Core.shared.identify(userId)
    }

    /// Manual conversion event. Deliberately minimal.
    public static func track(_ event: String, properties: [String: WayfindValue]? = nil) {
        Core.shared.track(event, properties: properties)
    }

    /// Override the auto-detected screen name for the current screen (emits a `manual` screen view).
    public static func setScreenName(_ name: String) {
        Core.shared.setScreenName(name)
    }
}

/// A JSON-scalar value usable in `track` properties.
public enum WayfindValue: Codable, Equatable {
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

extension WayfindValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}
extension WayfindValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
}
extension WayfindValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .number(value) }
}
extension WayfindValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}
