import Foundation

/// Fingerprints whose wireframe thumbnail was already captured on this device, so each screen is
/// rendered at most once (spec §3.3 step 5). File-backed in the same directory as the event queue;
/// persistence is best-effort — worst case a thumbnail is re-rendered and the server keeps the
/// first one it ever received (coalesce upsert), so retries are idempotent.
///
/// Not thread-safe on its own — `Core` serializes all access on its work queue.
final class ThumbnailRegistry {
    private static let maxEntries = 300

    private let fileURL: URL
    /// Insertion-ordered so eviction past the cap drops the oldest first.
    private var captured: [String]
    private var capturedSet: Set<String>

    /// - Parameter directory: Storage directory. Defaults to `Application Support/AnalyticsDrop`
    ///   (tests inject a temp directory).
    init(directory: URL? = nil) {
        let dir = directory ?? EventQueue.defaultDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("thumbnails.json")
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            captured = list
        } else {
            captured = []
        }
        capturedSet = Set(captured)
    }

    func needsCapture(_ fingerprint: String) -> Bool {
        !capturedSet.contains(fingerprint)
    }

    func markCaptured(_ fingerprint: String) {
        guard !capturedSet.contains(fingerprint) else { return }
        captured.append(fingerprint)
        capturedSet.insert(fingerprint)
        while captured.count > Self.maxEntries {
            capturedSet.remove(captured.removeFirst())
        }
        if let data = try? JSONEncoder().encode(captured) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
