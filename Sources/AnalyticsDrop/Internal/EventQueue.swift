import Foundation

/// Durable JSON-lines buffer for outbound events.
///
/// Two files, both in `Application Support/AnalyticsDrop` (excluded from iCloud backup):
///
/// - **live** (`events.jsonl`) mirrors the in-memory buffer so a crash between flushes doesn't
///   lose events; it is truncated on every drain.
/// - **spool** (`retry.jsonl`) holds events whose upload failed for a retriable reason. They are
///   re-sent on the next flush cycle and on the next launch, bounded by `maxSpoolBytes`
///   (oldest dropped first) and `maxAge`.
///
/// `Application Support` rather than `Caches`: `Caches` is purgeable under storage pressure, so
/// the crash-recovery path could come up empty exactly on the devices that needed it (#3).
///
/// Not thread-safe on its own — `Core` serializes all access on its work queue.
final class EventQueue {
    /// Encoded events, each ready to concatenate into a `{"batch":[…]}` body.
    private var buffer: [Data] = []

    private let liveURL: URL
    private let spoolURL: URL
    private let maxSpoolBytes: Int
    private let maxAge: TimeInterval
    private let encoder = JSONEncoder()

    /// - Parameters:
    ///   - directory: Storage directory. Defaults to `Application Support/AnalyticsDrop`
    ///     (tests inject a temp directory).
    ///   - maxSpoolBytes: Hard cap on retained failed events; oldest are dropped first.
    ///   - maxAge: Events older than this are dropped rather than re-sent.
    init(directory: URL? = nil, maxSpoolBytes: Int = 512 * 1024, maxAge: TimeInterval = 7 * 24 * 3600) {
        let dir = directory ?? Self.defaultDirectory()
        self.maxSpoolBytes = maxSpoolBytes
        self.maxAge = maxAge
        self.liveURL = dir.appendingPathComponent("events.jsonl")
        self.spoolURL = dir.appendingPathComponent("retry.jsonl")
        Self.prepare(directory: dir)
    }

    var count: Int { buffer.count }

    func append(_ event: WireEvent) {
        guard let line = try? encoder.encode(event) else { return }
        buffer.append(line)
        appendLines([line], to: liveURL)
    }

    /// Returns and clears the in-memory buffer, truncating the live file.
    func drainLines() -> [Data] {
        let out = buffer
        buffer.removeAll(keepingCapacity: true)
        remove(liveURL)
        return out
    }

    /// Lines left in the live file by a previous run (crash recovery). Clears the file.
    /// Call before the first `append` of this run.
    func takeRecoveredLines() -> [Data] {
        let lines = readLines(liveURL)
        remove(liveURL)
        return lines
    }

    /// Failed-upload lines awaiting retry. Clears the file — the caller owns them now and is
    /// expected to `spool` them again if the retry also fails.
    func takeSpooledLines() -> [Data] {
        let lines = readLines(spoolURL)
        remove(spoolURL)
        return lines
    }

    /// Retain lines whose upload failed for a retriable reason, enforcing the size cap.
    /// Returns how many lines the cap evicted (for debug logging).
    @discardableResult
    func spool(_ lines: [Data]) -> Int {
        var kept = readLines(spoolURL) + lines.filter { isWellFormed($0) }
        let considered = kept.count
        var bytes = kept.reduce(0) { $0 + $1.count + 1 }
        // The spool is append-ordered, so dropping from the front drops the oldest.
        while bytes > maxSpoolBytes, !kept.isEmpty {
            bytes -= kept.removeFirst().count + 1
        }
        remove(spoolURL)
        appendLines(kept, to: spoolURL)
        return considered - kept.count
    }

    /// Drop everything, in memory and on disk (runtime opt-out — #4).
    func discardAll() {
        buffer.removeAll(keepingCapacity: false)
        remove(liveURL)
        remove(spoolURL)
    }

    // MARK: - File helpers

    private func readLines(_ url: URL) -> [Data] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        let cutoff = Date().addingTimeInterval(-maxAge)
        return data.split(separator: 0x0a)
            .map { Data($0) }
            .filter { line in
                // A crash mid-append can leave a truncated line. One bad line would make the whole
                // concatenated batch a 400 (permanent) and take every good line down with it.
                guard isWellFormed(line) else { return false }
                guard let ts = EventLine.timestamp(line) else { return true }
                return ts >= cutoff
            }
    }

    private func isWellFormed(_ line: Data) -> Bool {
        guard !line.isEmpty else { return false }
        return (try? JSONSerialization.jsonObject(with: line)) is [String: Any]
    }

    private func appendLines(_ lines: [Data], to url: URL) {
        guard !lines.isEmpty else { return }
        var payload = Data()
        for line in lines {
            payload.append(line)
            payload.append(0x0a) // newline
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: payload)
        } else {
            try? payload.write(to: url, options: .atomic)
        }
    }

    private func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func defaultDirectory() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        return base.appendingPathComponent("AnalyticsDrop", isDirectory: true)
    }

    /// `Application Support` is not guaranteed to exist inside an app container; without this every
    /// write fails silently. Backup exclusion keeps analytics spool out of iCloud backups.
    private static func prepare(directory: URL) {
        var dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
    }
}

/// Reads metadata back out of an already-encoded event line without decoding the whole event.
enum EventLine {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let fallbackFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// The event's `ts`, parsed with the same options `ISO8601.string(from:)` writes.
    static func timestamp(_ line: Data) -> Date? {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let ts = obj["ts"] as? String
        else { return nil }
        return formatter.date(from: ts) ?? fallbackFormatter.date(from: ts)
    }
}
