import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Internal orchestrator. All mutable state is touched only on `queueSerial`; UIKit setup happens
/// on the main thread. Capture hooks and public API funnel through here.
final class Core {
    static let shared = Core()
    private init() {}

    private let queueSerial = DispatchQueue(label: "dev.analyticsdrop.core")

    private var config: AnalyticsDropConfig?
    private var identity: IdentityManager?
    private var queue: EventQueue?
    private var transport: APIClient?

    private var sessionId: String?
    private var seq = 0
    private var lastBackground: Date?
    private var endWork: DispatchWorkItem?
    private var flushTimer: DispatchSourceTimer?
    private var installed = false
    private var enabled = OptOutStore.shared.isEnabled
    /// True while a flush is in flight, so the retry spool isn't picked up twice. Only ever set
    /// while a completion is guaranteed to arrive — see `deactivate`.
    private var flushing = false

    // screen-view debounce
    private var lastFingerprint: String?
    private var lastFingerprintAt: Date?

    /// Set synchronously by `AnalyticsDrop.start` (before any queue hop) so the SwiftUI debug
    /// warning can tell "start() was never called" from "start() is still spinning up".
    private static let startedLock = NSLock()
    private static var startedFlag = false
    static var startCalled: Bool {
        get { startedLock.lock(); defer { startedLock.unlock() }; return startedFlag }
        set { startedLock.lock(); startedFlag = newValue; startedLock.unlock() }
    }

    // MARK: - Lifecycle

    func start(config: AnalyticsDropConfig) {
        queueSerial.async {
            guard self.config == nil else { return }
            self.config = config
            guard self.enabled else {
                // Opted out on a previous run: no swizzle, no session, no queue, nothing on disk.
                // `setEnabled(true)` activates from here without a relaunch.
                self.log("start() ignored — collection disabled by setEnabled(false)")
                return
            }
            self.activate()
        }

        guard OptOutStore.shared.isEnabled else { return }
        onMain {
            self.installIfNeeded()
            self.handleAppActive()
        }
    }

    /// Build the machinery and drain whatever the previous run left behind. Serial queue only.
    private func activate() {
        guard let config else { return }
        flushing = false
        identity = IdentityManager()
        let queue = EventQueue()
        self.queue = queue
        transport = APIClient(config: config)

        // Recovery: events the last run buffered but never flushed (crash), plus batches whose
        // upload failed for a retriable reason. Both go out as one batch; if that fails too they
        // land back in the spool.
        let pending = queue.takeRecoveredLines() + queue.takeSpooledLines()
        if !pending.isEmpty {
            log("resending \(pending.count) event(s) from the previous run")
            send(pending)
        }

        startFlushTimer()
        log("started (anon \(identity?.anonymousId.prefix(8) ?? "?"))")
    }

    /// Tear everything down and discard pending data. Serial queue only.
    private func deactivate() {
        flushTimer?.cancel()
        flushTimer = nil
        endWork?.cancel()
        endWork = nil
        sessionId = nil
        seq = 0
        lastFingerprint = nil
        lastFingerprintAt = nil
        // Discard, don't hold: a user who opts out must not ship their backlog on the next flush.
        queue?.discardAll()
        queue = nil
        transport = nil
        identity = nil
        // Releasing the transport means an in-flight completion may never arrive; leaving this set
        // would make every future flushNow() a no-op and stall delivery until the next launch.
        flushing = false
        log("collection disabled — pending events discarded")
    }

    /// Runtime opt-out (#4). The persisted choice is honoured by later launches too.
    func setEnabled(_ newValue: Bool) {
        OptOutStore.shared.isEnabled = newValue
        queueSerial.async {
            guard self.enabled != newValue else { return }
            self.enabled = newValue
            if newValue {
                guard self.config != nil else { return } // start() will activate when it's called
                self.activate()
                self.onMain {
                    self.installIfNeeded()
                    self.handleAppActive()
                }
            } else {
                self.deactivate()
            }
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
        flushTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queueSerial)
        timer.schedule(deadline: .now() + config.flushInterval, repeating: config.flushInterval)
        timer.setEventHandler { [weak self] in self?.flushNow() }
        timer.resume()
        flushTimer = timer
    }

    private func handleAppActive() {
        queueSerial.async {
            guard self.enabled, self.config != nil else { return }
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
            guard self.enabled else { return }
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
            guard self.enabled else { return }
            self.identity?.identify(userId)
            self.emit(.identify)
        }
    }

    func track(_ name: String, properties: [String: AnalyticsDropValue]?) {
        queueSerial.async {
            guard self.enabled else { return }
            self.emit(.track, track: WireTrack(name: name, properties: properties))
        }
    }

    func setScreenName(_ name: String) {
        queueSerial.async {
            guard self.enabled else { return }
            self.emit(.screenView, screen: WireScreen(fingerprint: name, kind: "manual", thumbnailPng: nil, name: name))
        }
    }

    /// Called by the capture layer (main thread). Debounces identical fingerprints (§3.2).
    /// `name` is an optional display-name hint derived from code identifiers (ScreenNameHint).
    func captureScreen(fingerprint: String, kind: String, name: String? = nil) {
        queueSerial.async {
            guard self.enabled else { return }
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
        guard enabled, let config, let identity, let queue else { return }
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
        guard enabled, let queue, !flushing else { return }
        // Everything the previous attempt couldn't deliver rides along with this batch.
        let lines = queue.takeSpooledLines() + queue.drainLines()
        guard !lines.isEmpty else { return }
        send(lines)
    }

    /// Upload, and keep the events if the failure was transient. Serial queue only.
    private func send(_ lines: [Data]) {
        guard let transport else {
            // The caller already drained these out of the buffer and the live file; without this
            // they would exist nowhere.
            queue?.spool(lines)
            return
        }
        flushing = true
        transport.uploadLines(lines) { [weak self] result in
            guard let self else { return }
            self.queueSerial.async {
                self.flushing = false
                guard result == .retriable else { return }
                guard self.enabled, let queue = self.queue else { return } // opted out mid-flight
                let evicted = queue.spool(lines)
                self.log("spooled \(lines.count) event(s) for retry\(evicted > 0 ? ", evicted \(evicted) over cap" : "")")
            }
        }
    }

    // MARK: - helpers

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    private func log(_ message: String) {
        if config?.debug == true { print("[AnalyticsDrop] \(message)") }
    }
}
