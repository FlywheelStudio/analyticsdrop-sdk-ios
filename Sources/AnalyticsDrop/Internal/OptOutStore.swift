import Foundation

/// Persists the runtime collection switch (`AnalyticsDrop.setEnabled`) so a consent choice made
/// mid-session survives relaunch — otherwise the next `start()` would quietly resume collecting
/// for a user who opted out (#4).
///
/// Defaults to **enabled** when the key was never written: an integrator who never calls
/// `setEnabled` gets today's behaviour, and `start()` remains the strongest off-switch.
struct OptOutStore {
    static let defaultsKey = "dev.analyticsdrop.collectionEnabled"
    static let shared = OptOutStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        // `bool(forKey:)` is false for an unset key, which would disable the SDK for every
        // existing integrator — so absence must be read as "enabled", explicitly.
        get { defaults.object(forKey: Self.defaultsKey) == nil ? true : defaults.bool(forKey: Self.defaultsKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.defaultsKey) }
    }

    /// Forget any stored choice (test support).
    func reset() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}
