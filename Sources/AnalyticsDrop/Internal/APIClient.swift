import Foundation

/// The disposition of an upload attempt, which decides whether the caller keeps the events.
enum UploadResult: Equatable {
    /// Accepted by the backend.
    case success
    /// The backend will never accept these events (bad key, malformed batch) — drop them.
    case permanent
    /// Transient (network, 5xx, 408, 429) — keep the events and try again later.
    case retriable
}

/// Uploads batches to `POST {endpoint}/v1/events` as gzip JSON (plain JSON fallback if
/// compression fails). Retries twice in-flight with backoff; anything still failing for a
/// retriable reason is handed back to `Core`, which spools it to disk for the next flush
/// cycle / next launch (#3).
final class APIClient {
    private let config: AnalyticsDropConfig
    private let session: URLSession
    private let eventsURL: URL

    init(config: AnalyticsDropConfig) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: cfg)
        self.eventsURL = config.endpoint.appendingPathComponent("v1/events")
    }

    /// Upload already-encoded event JSON lines (the queue's storage unit) without re-decoding.
    func uploadLines(_ lines: [Data], completion: @escaping (UploadResult) -> Void) {
        guard !lines.isEmpty else { completion(.success); return }
        var body = Data("{\"batch\":[".utf8)
        for (i, line) in lines.enumerated() {
            if i > 0 { body.append(0x2c) } // comma
            body.append(line)
        }
        body.append(Data("]}".utf8))
        send(body: body, attempt: 0, completion: completion)
    }

    /// Which failures are worth keeping events for. A 4xx means the backend rejected the request
    /// itself (bad key, malformed batch) and resending changes nothing — except 408/429, which
    /// explicitly mean "try again".
    static func classify(status: Int, error: Error?) -> UploadResult {
        if error != nil { return .retriable }
        if (200...299).contains(status) { return .success }
        if status == 408 || status == 429 { return .retriable }
        if (500...599).contains(status) { return .retriable }
        if (400...499).contains(status) { return .permanent }
        return .retriable // no HTTP response and no error — treat as transient
    }

    private func send(body: Data, attempt: Int, completion: @escaping (UploadResult) -> Void) {
        var req = URLRequest(url: eventsURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.apiKey, forHTTPHeaderField: "X-AnalyticsDrop-Key")
        if let gz = Gzip.compress(body) {
            req.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
            req.httpBody = gz
        } else {
            req.httpBody = body
        }

        session.dataTask(with: req) { [weak self] _, response, error in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            switch Self.classify(status: status, error: error) {
            case .success:
                self.log("flushed \(body.count)B (HTTP \(status))")
                completion(.success)
            case .permanent:
                self.log("dropped batch, backend rejected it (HTTP \(status))")
                completion(.permanent)
            case .retriable:
                guard attempt >= 2 else {
                    let delay = pow(2.0, Double(attempt)) // 1s, 2s
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        self.send(body: body, attempt: attempt + 1, completion: completion)
                    }
                    return
                }
                self.log("upload failed (status \(status), err \(String(describing: error))) — kept for retry")
                completion(.retriable)
            }
        }.resume()
    }

    private func log(_ message: String) {
        if config.debug { print("[AnalyticsDrop] \(message)") }
    }
}
