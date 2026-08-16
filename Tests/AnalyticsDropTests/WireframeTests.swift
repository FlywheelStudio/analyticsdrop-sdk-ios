import XCTest
@testable import AnalyticsDrop

/// The planner is pure Swift, so the privacy and determinism guarantees are tested here on any
/// platform — no UIKit needed (the UIKit collector/renderer only feed and consume plans).
final class WireframePlannerTests: XCTestCase {
    private let size = CGSize(width: 390, height: 844)

    private func fact(depth: Int = 0, x: CGFloat = 10, y: CGFloat = 10, w: CGFloat = 100,
                      h: CGFloat = 40, radius: CGFloat = 0, kind: WireFactKind,
                      fill: WireColor? = nil, lines: Int = 1,
                      textColor: WireColor? = nil) -> WireElementFact {
        WireElementFact(depth: depth, frame: CGRect(x: x, y: y, width: w, height: h),
                        radius: radius, kind: kind, fill: fill, lines: lines, textColor: textColor)
    }

    // Privacy invariant: the draw vocabulary is rounded rects only. `WireRectCommand` carries no
    // string other than nothing — its fill is four clamped numbers — so no app text can survive
    // into a plan. This test locks the shape so a future "text op" can't slip in unnoticed.
    func testPlanCarriesOnlyNumericRectCommands() throws {
        let plan = try XCTUnwrap(Wireframe.plan(
            facts: [
                fact(kind: .text, lines: 3, textColor: WireColor(r: 0, g: 0, b: 0)),
                fact(y: 100, kind: .image, fill: WireColor(r: 1, g: 0, b: 0)),
                fact(y: 200, kind: .control),
                fact(y: 300, kind: .block, fill: WireColor(r: 0.5, g: 0.5, b: 0.5)),
            ],
            size: size, pageBg: nil))
        let mirror = Mirror(reflecting: WireRectCommand(rect: .zero, radius: 0,
                                                        fill: Wireframe.pageFallback))
        XCTAssertEqual(mirror.children.map(\.label), ["rect", "radius", "fill"])
        XCTAssertGreaterThan(plan.commands.count, 1)
    }

    func testImageFillIsConstantAndNeverTheElementsOwnColor() throws {
        let hostile = WireColor(r: 0.123, g: 0.456, b: 0.789)
        let plan = try XCTUnwrap(Wireframe.plan(
            facts: [fact(kind: .image, fill: hostile)], size: size, pageBg: nil))
        XCTAssertEqual(plan.commands.count, 2) // page + image
        XCTAssertEqual(plan.commands[1].fill, Wireframe.imageFill)
    }

    func testMinSizeRuleSkipsSmallAndOffscreenElements() throws {
        let plan = try XCTUnwrap(Wireframe.plan(
            facts: [
                fact(w: 19, h: 100, kind: .block, fill: WireColor(r: 0, g: 0, b: 1)),
                fact(w: 100, h: 19, kind: .block, fill: WireColor(r: 0, g: 0, b: 1)),
                // Mostly off-canvas: visible part is under the minimum.
                fact(x: size.width - 10, w: 100, h: 100, kind: .block, fill: WireColor(r: 0, g: 0, b: 1)),
            ],
            size: size, pageBg: nil))
        XCTAssertEqual(plan.commands.count, 1) // page background only
    }

    func testTextBecomesCappedDeterministicBars() throws {
        let plan = try XCTUnwrap(Wireframe.plan(
            facts: [fact(h: 400, kind: .text, lines: 50, textColor: WireColor(r: 0, g: 0, b: 0))],
            size: size, pageBg: nil))
        let bars = Array(plan.commands.dropFirst())
        XCTAssertEqual(bars.count, Wireframe.maxTextBars)
        // Widths follow the fixed positional cycle — nothing about content can change them.
        for (i, bar) in bars.enumerated() {
            XCTAssertEqual(bar.rect.width, 100 * Wireframe.barWidths[i % Wireframe.barWidths.count],
                           accuracy: 0.001)
        }
        // Bars are faded: alpha reduced by the fixed factor.
        XCTAssertEqual(bars[0].fill.a, Wireframe.textBarAlpha, accuracy: 0.001)
    }

    func testTransparentBlockIsSkippedAndCommandCapHolds() throws {
        var facts: [WireElementFact] = [fact(kind: .block, fill: nil)]
        for i in 0..<2000 {
            facts.append(fact(y: CGFloat(i % 800), kind: .block, fill: WireColor(r: 0, g: 1, b: 0)))
        }
        let plan = try XCTUnwrap(Wireframe.plan(facts: facts, size: size, pageBg: nil))
        XCTAssertEqual(plan.commands.count, Wireframe.maxCommands)
    }

    func testPlanIsDeterministic() throws {
        let facts = [
            fact(depth: 2, kind: .block, fill: WireColor(r: 0.2, g: 0.4, b: 0.6)),
            fact(depth: 1, y: 60, kind: .control),
            fact(depth: 1, y: 120, kind: .text, lines: 2, textColor: WireColor(r: 0.1, g: 0.1, b: 0.1)),
        ]
        let a = try XCTUnwrap(Wireframe.plan(facts: facts, size: size, pageBg: Wireframe.pageFallback))
        let b = try XCTUnwrap(Wireframe.plan(facts: facts, size: size, pageBg: Wireframe.pageFallback))
        XCTAssertEqual(a.commands, b.commands)
        // Depth ordering: the depth-1 control paints before the depth-2 block.
        XCTAssertEqual(a.commands[1].fill, Wireframe.controlFill)
    }

    func testColorComponentsAreClamped() {
        let c = WireColor(r: 5, g: -1, b: 0.5, a: 9)
        XCTAssertEqual(c, WireColor(r: 1, g: 0, b: 0.5, a: 1))
    }
}

final class ThumbnailRegistryTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("adthumbs-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        try super.tearDownWithError()
    }

    func testMarkPersistsAcrossInstances() {
        let reg = ThumbnailRegistry(directory: dir)
        XCTAssertTrue(reg.needsCapture("fp_a"))
        reg.markCaptured("fp_a")
        XCTAssertFalse(reg.needsCapture("fp_a"))

        let fresh = ThumbnailRegistry(directory: dir)
        XCTAssertFalse(fresh.needsCapture("fp_a"))
        XCTAssertTrue(fresh.needsCapture("fp_b"))
    }

    func testEvictsOldestPastCap() {
        let reg = ThumbnailRegistry(directory: dir)
        for i in 0..<301 { reg.markCaptured("fp_\(i)") }
        XCTAssertTrue(reg.needsCapture("fp_0")) // oldest evicted
        XCTAssertFalse(reg.needsCapture("fp_300"))
        XCTAssertFalse(reg.needsCapture("fp_1"))
    }
}

final class AttachThumbnailTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("adattach-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        try super.tearDownWithError()
    }

    private func screenView(seq: Int, fingerprint: String) -> WireEvent {
        WireEvent(
            type: "screen_view", eventId: UUID().uuidString, anonymousId: "anon", userId: nil,
            sessionId: "s", seq: seq, ts: ISO8601.string(from: Date()),
            screen: WireScreen(fingerprint: fingerprint, kind: "swiftui", thumbnailPng: nil, name: nil),
            event: nil,
            context: WireContext(appVersion: "1", build: "1", os: "iOS", device: "d", sdk: "test"))
    }

    private func screen(of line: Data) -> [String: Any]? {
        ((try? JSONSerialization.jsonObject(with: line)) as? [String: Any])?["screen"] as? [String: Any]
    }

    func testAttachPatchesTheQueuedEventAndItsCrashMirror() throws {
        let q = EventQueue(directory: dir)
        q.append(screenView(seq: 1, fingerprint: "fp_a"))
        q.append(screenView(seq: 2, fingerprint: "fp_b"))

        XCTAssertTrue(q.attachThumbnail(fingerprint: "fp_a", base64Png: "PNGDATA"))

        // The crash-recovery file carries the patch too, not just the in-memory buffer.
        let recovered = EventQueue(directory: dir).takeRecoveredLines()
        XCTAssertEqual(recovered.count, 2)
        XCTAssertEqual(screen(of: recovered[0])?["thumbnailPng"] as? String, "PNGDATA")
        XCTAssertNil(screen(of: recovered[1])?["thumbnailPng"])
    }

    func testAttachFailsWhenEventAlreadyFlushed() {
        let q = EventQueue(directory: dir)
        q.append(screenView(seq: 1, fingerprint: "fp_a"))
        _ = q.drainLines()
        XCTAssertFalse(q.attachThumbnail(fingerprint: "fp_a", base64Png: "PNGDATA"))
    }

    func testAttachTargetsNewestMatchAndNeverOverwrites() throws {
        let q = EventQueue(directory: dir)
        q.append(screenView(seq: 1, fingerprint: "fp_a"))
        q.append(screenView(seq: 2, fingerprint: "fp_a"))

        XCTAssertTrue(q.attachThumbnail(fingerprint: "fp_a", base64Png: "FIRST"))
        XCTAssertTrue(q.attachThumbnail(fingerprint: "fp_a", base64Png: "SECOND"))

        let lines = q.drainLines()
        // Newest got the first attach; the second attach fell through to the older event.
        XCTAssertEqual(screen(of: lines[1])?["thumbnailPng"] as? String, "FIRST")
        XCTAssertEqual(screen(of: lines[0])?["thumbnailPng"] as? String, "SECOND")
    }
}
