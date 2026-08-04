import XCTest
@testable import AnalyticsDrop

/// Which upload failures are worth keeping events for (#3).
final class UploadClassificationTests: XCTestCase {
    func testSuccessRange() {
        XCTAssertEqual(APIClient.classify(status: 200, error: nil), .success)
        XCTAssertEqual(APIClient.classify(status: 202, error: nil), .success)
        XCTAssertEqual(APIClient.classify(status: 299, error: nil), .success)
    }

    func testNetworkErrorIsRetriable() {
        let err = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertEqual(APIClient.classify(status: 0, error: err), .retriable)
        // Even alongside a 2xx: the body may never have arrived.
        XCTAssertEqual(APIClient.classify(status: 200, error: err), .retriable)
    }

    func testServerErrorsAreRetriable() {
        for status in [500, 502, 503, 504, 599] {
            XCTAssertEqual(APIClient.classify(status: status, error: nil), .retriable, "HTTP \(status)")
        }
    }

    func testTimeoutAndRateLimitAreRetriable() {
        XCTAssertEqual(APIClient.classify(status: 408, error: nil), .retriable)
        XCTAssertEqual(APIClient.classify(status: 429, error: nil), .retriable)
    }

    func testClientErrorsArePermanent() {
        // Bad key or malformed batch: resending the same bytes changes nothing.
        for status in [400, 401, 403, 404, 413, 422] {
            XCTAssertEqual(APIClient.classify(status: status, error: nil), .permanent, "HTTP \(status)")
        }
    }

    func testNoResponseAndNoErrorIsRetriable() {
        XCTAssertEqual(APIClient.classify(status: 0, error: nil), .retriable)
    }
}

/// Runtime opt-out persistence (#4).
final class OptOutStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "adtest-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    func testDefaultsToEnabledWhenNeverSet() {
        // `UserDefaults.bool(forKey:)` returns false for a missing key — reading it naively would
        // disable the SDK for every integrator who never touches setEnabled.
        XCTAssertNil(defaults.object(forKey: OptOutStore.defaultsKey))
        XCTAssertTrue(OptOutStore(defaults: defaults).isEnabled)
    }

    func testOptOutPersistsAndIsReadableByAFreshStore() {
        OptOutStore(defaults: defaults).isEnabled = false
        // A "next launch" reading the same defaults must still see the opt-out.
        XCTAssertFalse(OptOutStore(defaults: defaults).isEnabled)
    }

    func testOptBackIn() {
        let store = OptOutStore(defaults: defaults)
        store.isEnabled = false
        store.isEnabled = true
        XCTAssertTrue(OptOutStore(defaults: defaults).isEnabled)
    }

    func testResetRestoresTheEnabledDefault() {
        let store = OptOutStore(defaults: defaults)
        store.isEnabled = false
        store.reset()
        XCTAssertTrue(store.isEnabled)
    }
}
