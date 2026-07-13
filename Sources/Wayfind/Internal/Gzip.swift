import Foundation
import Compression

/// Minimal gzip encoder: Apple's Compression framework emits raw DEFLATE for
/// `COMPRESSION_ZLIB`, so we add the gzip container ourselves (10-byte header +
/// CRC32 + input size trailer). Used for `POST /v1/events` bodies (§3.5); the
/// backend gunzips via the `Content-Encoding: gzip` header and magic-byte sniffing.
enum Gzip {
    /// Returns nil for empty input or if compression fails (caller sends plain JSON instead).
    static func compress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let dstCapacity = data.count + 4096
        var dst = Data(count: dstCapacity)
        let written = dst.withUnsafeMutableBytes { (dstPtr: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) -> Int in
                guard let dstBase = dstPtr.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = srcPtr.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(dstBase, dstCapacity, srcBase, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }

        // header: magic, deflate, no flags, mtime 0, no extra flags, unknown OS
        var out = Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff])
        out.append(dst.prefix(written))
        var crc = crc32(data).littleEndian
        var isize = UInt32(truncatingIfNeeded: data.count).littleEndian
        withUnsafeBytes(of: &crc) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: &isize) { out.append(contentsOf: $0) }
        return out
    }

    private static let crcTable: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) == 1 ? 0xedb8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xffff_ffff
        for byte in data { c = crcTable[Int((c ^ UInt32(byte)) & 0xff)] ^ (c >> 8) }
        return c ^ 0xffff_ffff
    }
}
