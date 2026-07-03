import Foundation

/// In-memory buffer with best-effort JSON-lines persistence in Caches (crash safety, §3.5).
/// Not thread-safe on its own — `Core` serializes all access on its work queue.
final class EventQueue {
    private var buffer: [WireEvent] = []
    private let fileURL: URL
    private let encoder = JSONEncoder()

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        fileURL = (caches ?? FileManager.default.temporaryDirectory).appendingPathComponent("wayfind-events.jsonl")
    }

    var count: Int { buffer.count }

    func append(_ event: WireEvent) {
        buffer.append(event)
        if let line = try? encoder.encode(event) {
            persist(line)
        }
    }

    /// Returns and clears the in-memory buffer, truncating the persistence file.
    func drain() -> [WireEvent] {
        let out = buffer
        buffer.removeAll(keepingCapacity: true)
        try? FileManager.default.removeItem(at: fileURL)
        return out
    }

    /// Raw encoded JSON lines left over from a previous run (crash recovery). Each element is one
    /// already-encoded event object, suitable for wrapping into a batch without decoding.
    func loadPersistedLines() -> [Data] {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return [] }
        return data.split(separator: 0x0a).map { Data($0) }.filter { !$0.isEmpty }
    }

    func clearPersisted() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func persist(_ line: Data) {
        var payload = line
        payload.append(0x0a) // newline
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: payload)
        } else {
            try? payload.write(to: fileURL, options: .atomic)
        }
    }
}
