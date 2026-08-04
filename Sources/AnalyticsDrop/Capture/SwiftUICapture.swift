#if canImport(SwiftUI)
import SwiftUI

public extension View {
    /// Attach once at the SwiftUI root:
    /// `WindowGroup { ContentView().analyticsDropTracked() }`
    ///
    /// **This modifier does not enable capture, and does not scope it.** In 0.2.x it is a
    /// forward-compatible no-op: automatic screen capture comes entirely from
    /// `AnalyticsDrop.start(...)`, which installs a global `UIViewController.viewDidAppear`
    /// swizzle — that fires for the `UIHostingController`s backing `NavigationStack` pushes,
    /// sheets, and `TabView` switches, wherever they are in the hierarchy. Applying the modifier
    /// to a subtree therefore captures the whole app, not that subtree, and omitting `start()`
    /// captures nothing (#1). Kept as the documented integration point and the home for richer
    /// navigation observation later (Mechanism A).
    ///
    /// In DEBUG builds it logs once if `start()` has not been called, since that combination is
    /// always a mistake.
    func analyticsDropTracked() -> some View {
        onAppear {
            #if DEBUG
            AnalyticsDropDebug.warnIfNotStarted()
            #endif
        }
    }

    /// Escape hatch for exact naming of a specific SwiftUI screen (mirrors `AnalyticsDrop.setScreenName`).
    /// `SomeView().analyticsDropScreen("Checkout")`
    func analyticsDropScreen(_ name: String) -> some View {
        onAppear { AnalyticsDrop.setScreenName(name) }
    }
}

/// Debug-build integration checks. No-ops in release.
enum AnalyticsDropDebug {
    private static let lock = NSLock()
    private static var warned = false

    static func warnIfNotStarted() {
        guard !Core.startCalled else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !warned else { return }
        warned = true
        print("""
        [AnalyticsDrop] .analyticsDropTracked() was applied but AnalyticsDrop.start(...) has not \
        been called — nothing will be captured. The modifier is a no-op; start() is what installs \
        capture. (Intentionally gating this build? Ignore this message; it is DEBUG-only.)
        """)
    }
}
#endif
