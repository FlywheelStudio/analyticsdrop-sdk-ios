import XCTest
import Compression
@testable import AnalyticsDrop

final class GzipTests: XCTestCase {
    func testCrc32KnownVector() {
        // Standard CRC-32 check value.
        XCTAssertEqual(Gzip.crc32(Data("123456789".utf8)), 0xCBF4_3926)
    }

    func testCompressProducesValidGzipContainer() throws {
        let input = Data(String(repeating: "{\"type\":\"screen_view\"}", count: 50).utf8)
        let gz = try XCTUnwrap(Gzip.compress(input))

        // gzip magic + deflate method
        XCTAssertEqual([UInt8](gz.prefix(3)), [0x1f, 0x8b, 0x08])
        XCTAssertLessThan(gz.count, input.count) // repetitive JSON must actually compress

        // trailer: CRC32 + ISIZE (little endian)
        let trailer = [UInt8](gz.suffix(8))
        let crc = UInt32(trailer[0]) | UInt32(trailer[1]) << 8 | UInt32(trailer[2]) << 16 | UInt32(trailer[3]) << 24
        let isize = UInt32(trailer[4]) | UInt32(trailer[5]) << 8 | UInt32(trailer[6]) << 16 | UInt32(trailer[7]) << 24
        XCTAssertEqual(crc, Gzip.crc32(input))
        XCTAssertEqual(isize, UInt32(input.count))

        // deflate payload between header (10B) and trailer (8B) must inflate back to the input
        let deflated = gz.dropFirst(10).dropLast(8)
        let dstCapacity = input.count + 64
        var dst = Data(count: dstCapacity)
        let written = dst.withUnsafeMutableBytes { (dstPtr: UnsafeMutableRawBufferPointer) -> Int in
            deflated.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) -> Int in
                guard let dstBase = dstPtr.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = srcPtr.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dstBase, dstCapacity, srcBase, deflated.count, nil, COMPRESSION_ZLIB)
            }
        }
        XCTAssertEqual(dst.prefix(written), input)
    }

    func testEmptyInputReturnsNil() {
        XCTAssertNil(Gzip.compress(Data()))
    }
}

final class EventQueueTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Injected temp directory: the real one is the app's Application Support container, which
        // under `swift test` on macOS would be the developer's own ~/Library/Application Support.
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("adq-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        try super.tearDownWithError()
    }

    private func makeQueue(maxSpoolBytes: Int = 512 * 1024, maxAge: TimeInterval = 7 * 24 * 3600) -> EventQueue {
        EventQueue(directory: dir, maxSpoolBytes: maxSpoolBytes, maxAge: maxAge)
    }

    private func makeEvent(seq: Int, at date: Date = Date()) -> WireEvent {
        WireEvent(
            type: "screen_view", eventId: UUID().uuidString, anonymousId: "anon", userId: nil,
            sessionId: "s", seq: seq, ts: ISO8601.string(from: date),
            screen: WireScreen(fingerprint: "F\(seq)", kind: "uikit", thumbnailPng: nil, name: nil),
            event: nil,
            context: WireContext(appVersion: "1", build: "1", os: "iOS", device: "d", sdk: "test"))
    }

    private func line(_ seq: Int, at date: Date = Date()) -> Data {
        try! JSONEncoder().encode(makeEvent(seq: seq, at: date))
    }

    private func object(_ line: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
    }

    func testAppendPersistsJsonLines() {
        let q = makeQueue()
        q.append(makeEvent(seq: 1))
        q.append(makeEvent(seq: 2))
        XCTAssertEqual(q.count, 2)

        // A "new run" (fresh instance) sees the persisted lines — the crash-recovery path.
        let recovered = makeQueue().takeRecoveredLines()
        XCTAssertEqual(recovered.count, 2)
        for line in recovered {
            XCTAssertEqual(object(line)?["type"] as? String, "screen_view")
        }
    }

    func testDrainClearsBufferAndFile() {
        let q = makeQueue()
        q.append(makeEvent(seq: 1))
        XCTAssertEqual(q.drainLines().count, 1)
        XCTAssertEqual(q.count, 0)
        XCTAssertTrue(makeQueue().takeRecoveredLines().isEmpty)
    }

    func testDefaultStorageIsApplicationSupportNotCaches() {
        // Regression guard for #3: Caches is purgeable under storage pressure, so the
        // crash-recovery file must not live there.
        let path = EventQueue.defaultDirectory().path
        XCTAssertTrue(path.hasSuffix("/AnalyticsDrop"), path)
        XCTAssertTrue(path.contains("Application Support"), path)
        XCTAssertFalse(path.contains("Caches"), path)
    }

    func testStorageDirectoryIsCreatedAndExcludedFromBackup() throws {
        _ = makeQueue() // init prepares the directory
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
        let excluded = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        XCTAssertEqual(excluded, true)
    }

    // MARK: - retry spool (#3)

    func testSpooledLinesSurviveAcrossInstances() {
        makeQueue().spool([line(1), line(2)])
        let next = makeQueue()
        XCTAssertEqual(next.takeSpooledLines().count, 2)
        XCTAssertTrue(makeQueue().takeSpooledLines().isEmpty, "taking the spool clears it")
    }

    func testSpoolAccumulatesAcrossFailures() {
        let q = makeQueue()
        q.spool([line(1)])
        q.spool([line(2)])
        XCTAssertEqual(q.takeSpooledLines().count, 2)
    }

    func testSpoolDropsOldestOverByteCap() {
        let one = line(1)
        let cap = (one.count + 1) * 2 // room for exactly two lines
        let q = makeQueue(maxSpoolBytes: cap)
        q.spool([line(1), line(2)])
        let evicted = q.spool([line(3)])
        XCTAssertEqual(evicted, 1)

        let kept = q.takeSpooledLines()
        XCTAssertEqual(kept.count, 2)
        let seqs = kept.compactMap { object($0)?["seq"] as? Int }
        XCTAssertEqual(seqs, [2, 3], "oldest is dropped first")
    }

    func testSpoolDropsEventsPastMaxAge() {
        let q = makeQueue(maxAge: 60)
        q.spool([line(1, at: Date().addingTimeInterval(-3600)), line(2)])
        let kept = q.takeSpooledLines()
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(EventLine.timestamp(kept[0])?.timeIntervalSinceNow ?? -999, 0, accuracy: 5)
    }

    func testMalformedLinesAreSkipped() throws {
        // A crash mid-append can truncate the last line; it must not poison the whole batch.
        _ = makeQueue() // creates the storage directory
        let good = line(1)
        var raw = Data()
        raw.append(good); raw.append(0x0a)
        raw.append(Data("{\"type\":\"screen_v".utf8)); raw.append(0x0a)
        try raw.write(to: dir.appendingPathComponent("retry.jsonl"))

        XCTAssertEqual(makeQueue().takeSpooledLines().count, 1)
    }

    func testDiscardAllClearsBufferAndBothFiles() {
        let q = makeQueue()
        q.append(makeEvent(seq: 1))
        q.spool([line(2)])
        q.discardAll()
        XCTAssertEqual(q.count, 0)
        let fresh = makeQueue()
        XCTAssertTrue(fresh.takeRecoveredLines().isEmpty)
        XCTAssertTrue(fresh.takeSpooledLines().isEmpty)
    }

    func testTimestampRoundTripsWhatTheEncoderWrites() {
        let now = Date()
        let parsed = EventLine.timestamp(line(1, at: now))
        XCTAssertNotNil(parsed, "age cap silently no-ops if ts can't be parsed back")
        XCTAssertEqual(parsed?.timeIntervalSince1970 ?? 0, now.timeIntervalSince1970, accuracy: 0.01)
    }
}
