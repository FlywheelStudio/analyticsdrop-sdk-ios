import Foundation
#if canImport(UIKit)
import UIKit
#endif

// Wire format (§3.6). Encodable only — the SDK never decodes events.

struct WireBatch: Encodable {
    let batch: [WireEvent]
}

struct WireEvent: Encodable {
    let type: String // screen_view | track | identify | session_start | session_end
    let eventId: String
    let anonymousId: String
    let userId: String?
    let sessionId: String
    let seq: Int
    let ts: String
    let screen: WireScreen?
    let event: WireTrack?
    let context: WireContext
}

struct WireScreen: Encodable {
    let fingerprint: String
    let kind: String // uikit | swiftui | manual
    let thumbnailPng: String?
    /// Inferred display name (type/class derived, never user content — see ScreenNameHint).
    let name: String?
}

struct WireTrack: Encodable {
    let name: String
    let properties: [String: AnalyticsDropValue]?
}

struct WireContext: Encodable {
    let appVersion: String
    let build: String
    let os: String
    let device: String
    let sdk: String
}

enum WireEventType: String {
    case screenView = "screen_view"
    case track
    case identify
    case sessionStart = "session_start"
    case sessionEnd = "session_end"
}

enum SDKInfo {
    static let version = "analyticsdrop-ios/0.2.0"
}

/// One-time device/app context snapshot.
enum DeviceContext {
    static let shared: WireContext = build()

    private static func build() -> WireContext {
        let info = Bundle.main.infoDictionary
        let appVersion = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        #if canImport(UIKit)
        let osVersion = UIDevice.current.systemVersion
        #else
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #endif
        return WireContext(
            appVersion: appVersion,
            build: build,
            os: "iOS \(osVersion)",
            device: hardwareModel(),
            sdk: SDKInfo.version
        )
    }

    private static func hardwareModel() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let mirror = Mirror(reflecting: sysinfo.machine)
        let id = mirror.children.reduce(into: "") { acc, el in
            if let v = el.value as? Int8, v != 0 { acc.append(Character(UnicodeScalar(UInt8(v)))) }
        }
        return id.isEmpty ? "unknown" : id
    }
}

enum ISO8601 {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static func string(from date: Date) -> String { formatter.string(from: date) }
}
