import XCTest
@testable import Wayfind

final class WayfindTests: XCTestCase {
    func testWayfindValueEncoding() throws {
        let enc = JSONEncoder()
        XCTAssertEqual(String(data: try enc.encode(WayfindValue.string("x")), encoding: .utf8), "\"x\"")
        XCTAssertEqual(String(data: try enc.encode(WayfindValue.number(9.99)), encoding: .utf8), "9.99")
        XCTAssertEqual(String(data: try enc.encode(WayfindValue.bool(true)), encoding: .utf8), "true")
    }

    func testWayfindValueLiterals() {
        let props: [String: WayfindValue] = ["plan": "pro", "price": 9.99, "trial": true, "count": 3]
        XCTAssertEqual(props["plan"], .string("pro"))
        XCTAssertEqual(props["price"], .number(9.99))
        XCTAssertEqual(props["trial"], .bool(true))
        XCTAssertEqual(props["count"], .number(3))
    }

    func testWireBatchEncodingOmitsNilUserId() throws {
        let ev = WireEvent(
            type: "screen_view", eventId: "e", anonymousId: "a", userId: nil, sessionId: "s",
            seq: 1, ts: "t",
            screen: WireScreen(fingerprint: "F", kind: "uikit", thumbnailPng: nil, name: nil),
            event: nil,
            context: WireContext(appVersion: "1", build: "1", os: "iOS", device: "d", sdk: "wayfind-ios/0.1.0")
        )
        let json = String(data: try JSONEncoder().encode(WireBatch(batch: [ev])), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"batch\""))
        XCTAssertTrue(json.contains("screen_view"))
        XCTAssertFalse(json.contains("userId")) // nil optionals are omitted, matching backend contract
    }
}
