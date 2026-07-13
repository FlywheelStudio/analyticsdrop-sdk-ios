import Foundation

/// Uploads batches to `POST {endpoint}/v1/events` as gzip JSON (plain JSON fallback if
/// compression fails). 2 retries with backoff on 5xx/network failure, then the batch is
/// dropped (no dead-letter — POC, §3.5).
final class APIClient {
    private let config: WayfindConfig
    private let session: URLSession
    private let eventsURL: URL

    init(config: WayfindConfig) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: cfg)
        self.eventsURL = config.endpoint.appendingPathComponent("v1/events")
    }

    /// Encodes and uploads a batch. Completion is called with success/failure after retries.
    func upload(_ batch: WireBatch, completion: @escaping (Bool) -> Void) {
        let body: Data
        do {
            body = try JSONEncoder().encode(batch)
        } catch {
            log("encode failed: \(error)")
            completion(false)
            return
        }
        send(body: body, attempt: 0, completion: completion)
    }

    /// Upload already-encoded event JSON lines (crash recovery) without re-decoding them.
    func uploadRaw(_ lines: [Data], completion: @escaping (Bool) -> Void) {
        guard !lines.isEmpty else { completion(true); return }
        var body = Data("{\"batch\":[".utf8)
        for (i, line) in lines.enumerated() {
            if i > 0 { body.append(0x2c) } // comma
            body.append(line)
        }
        body.append(Data("]}".utf8))
        send(body: body, attempt: 0, completion: completion)
    }

    private func send(body: Data, attempt: Int, completion: @escaping (Bool) -> Void) {
        var req = URLRequest(url: eventsURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.apiKey, forHTTPHeaderField: "X-Wayfind-Key")
        if let gz = Gzip.compress(body) {
            req.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
            req.httpBody = gz
        } else {
            req.httpBody = body
        }

        session.dataTask(with: req) { [weak self] _, response, error in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let retriable = error != nil || (500...599).contains(status)

            if !retriable {
                let ok = (200...299).contains(status)
                self.log(ok ? "flushed \(body.count)B (HTTP \(status))" : "dropped batch (HTTP \(status))")
                completion(ok)
                return
            }
            if attempt >= 2 {
                self.log("dropped batch after retries (status \(status), err \(String(describing: error)))")
                completion(false)
                return
            }
            let delay = pow(2.0, Double(attempt)) // 1s, 2s
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                self.send(body: body, attempt: attempt + 1, completion: completion)
            }
        }.resume()
    }

    private func log(_ message: String) {
        if config.debug { print("[Wayfind] \(message)") }
    }
}
