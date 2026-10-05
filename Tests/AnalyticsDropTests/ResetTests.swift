import XCTest
@testable import AnalyticsDrop

/// `reset()` — logout / account deletion (decision 005).
final class IdentityResetTests: XCTestCase {
    private var service: String!

    override func setUp() {
        super.setUp()
        service = "dev.analyticsdrop.sdk.test-\(UUID().uuidString)"
    }

    override func tearDown() {
        IdentityManager.deletePersistedId(service: service)
        super.tearDown()
    }

    func testIdIsStableAcrossInstancesUntilReset() {
        let first = IdentityManager(service: service).anonymousId
        XCTAssertEqual(IdentityManager(service: service).anonymousId, first)
    }

    func testResetClearsUserIdAndRotatesThePersistedId() {
        let identity = IdentityManager(service: service)
        let old = identity.anonymousId
        identity.identify("user_1")

        identity.reset()

        XCTAssertNil(identity.externalUserId)
        XCTAssertNotEqual(identity.anonymousId, old)
        // The next launch must read the new id. A plain SecItemAdd over the existing item fails
        // with errSecDuplicateItem and would leave `old` in place.
        XCTAssertEqual(IdentityManager(service: service).anonymousId, identity.anonymousId)
    }

    func testStaticRotationReplacesAnExistingItem() {
        let old = IdentityManager(service: service).anonymousId
        let fresh = IdentityManager.rotatePersistedId(service: service)
        XCTAssertNotEqual(fresh, old)
        XCTAssertEqual(IdentityManager.persistedId(service: service), fresh)
    }
}

final class CoreResetTests: XCTestCase {
    private var service: String!
    private var dir: URL!
    private var suiteName: String!
    private var optOut: OptOutStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        service = "dev.analyticsdrop.sdk.test-\(UUID().uuidString)"
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("adreset-\(UUID().uuidString)", isDirectory: true)
        suiteName = "adtest-\(UUID().uuidString)"
        optOut = OptOutStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
    }

    override func tearDownWithError() throws {
        IdentityManager.deletePersistedId(service: service)
        try? FileManager.default.removeItem(at: dir)
        UserDefaults().removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func makeCore() -> Core {
        Core(optOut: optOut, identityService: service, queueDirectory: dir)
    }

    private func start(_ core: Core) {
        // Port 9 (discard): nothing here reaches the flush threshold or the 30 s timer, so no
        // upload is attempted while the test runs.
        core.start(config: AnalyticsDropConfig(
            apiKey: "ad_test", endpoint: URL(string: "http://127.0.0.1:9")!, debug: false))
    }

    func testResetEndsTheSessionUnderTheOldIdentityAndContinuesUnderANewOne() throws {
        let core = makeCore()
        start(core)
        core.identify("user_1")
        core.track("before", properties: nil)
        core.reset()
        core.track("after", properties: nil)

        let events = core.drainQueuedEventsForTesting()
        XCTAssertEqual(events.map { $0["type"] as? String },
                       ["session_start", "identify", "track", "session_end", "session_start", "track"])

        let oldAnon = try XCTUnwrap(events[0]["anonymousId"] as? String)
        let end = events[3]
        XCTAssertEqual(end["anonymousId"] as? String, oldAnon)
        XCTAssertEqual(end["userId"] as? String, "user_1")

        let newAnon = try XCTUnwrap(events[4]["anonymousId"] as? String)
        XCTAssertNotEqual(newAnon, oldAnon)
        XCTAssertNotEqual(events[4]["sessionId"] as? String, end["sessionId"] as? String)
        XCTAssertEqual(events[5]["anonymousId"] as? String, newAnon)
        XCTAssertNil(events[5]["userId"], "the forgotten user id must not ride on later events")
        XCTAssertEqual(events[5]["seq"] as? Int, 2, "the new session restarts seq")

        XCTAssertEqual(IdentityManager.persistedId(service: service), newAnon)
    }

    func testResetWhileOptedOutEmitsNothingButRotatesThePersistedId() {
        let before = IdentityManager.rotatePersistedId(service: service)
        optOut.isEnabled = false
        let core = makeCore()
        start(core)

        core.reset()

        XCTAssertTrue(core.drainQueuedEventsForTesting().isEmpty)
        XCTAssertNil(core.anonymousIdForTesting)
        let after = IdentityManager.persistedId(service: service)
        XCTAssertNotNil(after)
        XCTAssertNotEqual(after, before)
    }

    func testResetBeforeStartRotatesTheIdTheNextStartUses() {
        let before = IdentityManager.rotatePersistedId(service: service)
        let core = makeCore()

        core.reset()
        let rotated = core.syncForTesting { IdentityManager.persistedId(service: service) }
        XCTAssertNotEqual(rotated, before)

        start(core)
        XCTAssertEqual(core.anonymousIdForTesting, rotated)
    }
}
