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
    private func makeEvent(seq: Int) -> WireEvent {
        WireEvent(
            type: "screen_view", eventId: UUID().uuidString, anonymousId: "anon", userId: nil,
            sessionId: "s", seq: seq, ts: "t",
            screen: WireScreen(fingerprint: "F\(seq)", kind: "uikit", thumbnailPng: nil, name: nil),
            event: nil,
            context: WireContext(appVersion: "1", build: "1", os: "iOS", device: "d", sdk: "test"))
    }

    override func setUp() {
        super.setUp()
        EventQueue().clearPersisted() // shared Caches file — start each test clean
    }

    func testAppendPersistsJsonLines() {
        let q = EventQueue()
        q.append(makeEvent(seq: 1))
        q.append(makeEvent(seq: 2))
        XCTAssertEqual(q.count, 2)

        // A "new run" (fresh instance) sees the persisted lines — the crash-recovery path.
        let recovered = EventQueue().loadPersistedLines()
        XCTAssertEqual(recovered.count, 2)
        for line in recovered {
            let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
            XCTAssertEqual(obj??["type"] as? String, "screen_view")
        }
    }

    func testDrainClearsBufferAndFile() {
        let q = EventQueue()
        q.append(makeEvent(seq: 1))
        let drained = q.drain()
        XCTAssertEqual(drained.count, 1)
        XCTAssertEqual(q.count, 0)
        XCTAssertTrue(EventQueue().loadPersistedLines().isEmpty)
    }
}
