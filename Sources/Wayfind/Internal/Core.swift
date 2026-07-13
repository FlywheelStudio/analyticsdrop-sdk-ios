import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Internal orchestrator. All mutable state is touched only on `queueSerial`; UIKit setup happens
/// on the main thread. Capture hooks and public API funnel through here.
final class Core {
    static let shared = Core()
    private init() {}

    private let queueSerial = DispatchQueue(label: "dev.wayfind.core")

    private var config: WayfindConfig?
    private var identity: IdentityManager?
    private var queue: EventQueue?
    private var transport: APIClient?

    private var sessionId: String?
    private var seq = 0
    private var lastBackground: Date?
    private var endWork: DispatchWorkItem?
    private var flushTimer: DispatchSourceTimer?
    private var installed = false

    // screen-view debounce
    private var lastFingerprint: String?
    private var lastFingerprintAt: Date?

    // MARK: - Lifecycle

    func start(config: WayfindConfig) {
        queueSerial.async {
            guard self.config == nil else { return }
            self.config = config
            self.identity = IdentityManager()
            self.queue = EventQueue()
            self.transport = APIClient(config: config)

            // Crash recovery: capture prior-run lines, clear the file so this run starts fresh, resend.
            if let q = self.queue {
                let lines = q.loadPersistedLines()
                q.clearPersisted()
                if !lines.isEmpty { self.transport?.uploadRaw(lines) { _ in } }
            }

            self.startFlushTimer()
            self.log("started (anon \(self.identity?.anonymousId.prefix(8) ?? "?"))")
        }

        onMain {
            self.installIfNeeded()
            self.handleAppActive()
        }
    }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        #if canImport(UIKit)
        UIKitCapture.installSwizzle()
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.handleAppActive()
        }
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.handleAppBackground()
        }
        #endif
    }

    private func startFlushTimer() {
        guard let config else { return }
        let timer = DispatchSource.makeTimerSource(queue: queueSerial)
        timer.schedule(deadline: .now() + config.flushInterval, repeating: config.flushInterval)
        timer.setEventHandler { [weak self] in self?.flushNow() }
        timer.resume()
        flushTimer = timer
    }

    private func handleAppActive() {
        queueSerial.async {
            guard self.config != nil else { return }
            self.endWork?.cancel()
            self.endWork = nil
            if self.sessionId == nil {
                self.beginSession()
            } else if let lb = self.lastBackground,
                      Date().timeIntervalSince(lb) > (self.config?.sessionGrace ?? 30) {
                self.endSession()
                self.beginSession()
            }
            self.lastBackground = nil
        }
    }

    private func handleAppBackground() {
        queueSerial.async {
            self.lastBackground = Date()
            self.flushNow()
            let grace = self.config?.sessionGrace ?? 30
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.lastBackground != nil { self.endSession() }
            }
            self.endWork = work
            self.queueSerial.asyncAfter(deadline: .now() + grace, execute: work)
        }
    }

    private func beginSession() {
        sessionId = UUID().uuidString
        seq = 0
        lastFingerprint = nil
        lastFingerprintAt = nil
        emit(.sessionStart)
    }

    private func endSession() {
        guard sessionId != nil else { return }
        emit(.sessionEnd)
        sessionId = nil
    }

    // MARK: - Public API entry points (dispatch onto the serial queue)

    func identify(_ userId: String) {
        queueSerial.async {
            self.identity?.identify(userId)
            self.emit(.identify)
        }
    }

    func track(_ name: String, properties: [String: WayfindValue]?) {
        queueSerial.async {
            self.emit(.track, track: WireTrack(name: name, properties: properties))
        }
    }

    func setScreenName(_ name: String) {
        queueSerial.async {
            self.emit(.screenView, screen: WireScreen(fingerprint: name, kind: "manual", thumbnailPng: nil, name: name))
        }
    }

    /// Called by the capture layer (main thread). Debounces identical fingerprints (§3.2).
    /// `name` is an optional display-name hint derived from code identifiers (ScreenNameHint).
    func captureScreen(fingerprint: String, kind: String, name: String? = nil) {
        queueSerial.async {
            let now = Date()
            if let last = self.lastFingerprint, last == fingerprint,
               let at = self.lastFingerprintAt,
               now.timeIntervalSince(at) < (self.config?.debounceInterval ?? 0.3) {
                return
            }
            self.lastFingerprint = fingerprint
            self.lastFingerprintAt = now
            self.emit(.screenView, screen: WireScreen(fingerprint: fingerprint, kind: kind, thumbnailPng: nil, name: name))
        }
    }

    // MARK: - Emit / flush (serial queue only)

    private func emit(_ type: WireEventType, screen: WireScreen? = nil, track: WireTrack? = nil) {
        guard let config, let identity, let queue else { return }
        if sessionId == nil && type != .sessionStart { beginSession() }
        guard let sid = sessionId else { return }
        seq += 1
        let event = WireEvent(
            type: type.rawValue,
            eventId: UUID().uuidString,
            anonymousId: identity.anonymousId,
            userId: identity.externalUserId,
            sessionId: sid,
            seq: seq,
            ts: ISO8601.string(from: Date()),
            screen: screen,
            event: track,
            context: DeviceContext.shared
        )
        queue.append(event)
        log("\(type.rawValue) seq=\(seq) \(screen?.fingerprint ?? track?.name ?? "")")
        if queue.count >= config.flushThreshold { flushNow() }
    }

    private func flushNow() {
        guard let transport, let queue, queue.count > 0 else { return }
        let events = queue.drain()
        transport.upload(WireBatch(batch: events)) { _ in }
    }

    // MARK: - helpers

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    private func log(_ message: String) {
        if config?.debug == true { print("[Wayfind] \(message)") }
    }
}
