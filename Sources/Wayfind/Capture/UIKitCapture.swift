#if canImport(UIKit)
import UIKit
import ObjectiveC.runtime

/// Mechanism for UIKit (§3.2) and the entry signal for SwiftUI (§3.3 Mechanism B). Swizzles
/// `viewDidAppear`; the hook stays trivial (flag + dispatch), all work happens off the hook.
enum UIKitCapture {
    private static var didSwizzle = false
    private static let uikitBundle = Bundle(for: UIView.self)

    static func installSwizzle() {
        guard !didSwizzle else { return }
        didSwizzle = true
        let cls = UIViewController.self
        guard
            let original = class_getInstanceMethod(cls, #selector(UIViewController.viewDidAppear(_:))),
            let swizzled = class_getInstanceMethod(cls, #selector(UIViewController.wf_viewDidAppear(_:)))
        else { return }
        method_exchangeImplementations(original, swizzled)
    }

    static func handle(_ vc: UIViewController) {
        let className = NSStringFromClass(type(of: vc))

        // Hosting controllers back SwiftUI screens; their class name is useless, so route to the
        // fingerprint path (Mechanism B -> C). Checked before system filtering (mangled generic
        // names start with "_").
        if className.contains("HostingController") {
            // Mechanism A (name inference): the hosting controller's generic parameters often
            // name the root SwiftUI view (e.g. UIHostingController<DetailView>). Derived from
            // type names only — never titles/content (privacy invariant).
            let hint = ScreenNameHint.fromHostingClass(String(describing: type(of: vc)))
            DispatchQueue.main.async {
                if let fp = ScreenFingerprint.current() {
                    Core.shared.captureScreen(fingerprint: fp, kind: "swiftui", name: hint)
                }
            }
            return
        }

        if isContainerOrSystem(vc, className) { return }

        // Leaf UIKit content controller: identity is the class name (e.g. CheckoutViewController).
        let name = String(describing: type(of: vc))
        Core.shared.captureScreen(fingerprint: name, kind: "uikit", name: ScreenNameHint.fromUIKitClass(name))
    }

    private static func isContainerOrSystem(_ vc: UIViewController, _ className: String) -> Bool {
        if vc is UINavigationController || vc is UITabBarController || vc is UISplitViewController
            || vc is UIPageViewController || vc is UIAlertController || vc is UIInputViewController {
            return true
        }
        if className.hasPrefix("_") { return true }
        // System-provided controllers live in the UIKitCore bundle; app screens live in the app bundle.
        if Bundle(for: type(of: vc)) == uikitBundle { return true }
        return false
    }
}

extension UIViewController {
    @objc fileprivate func wf_viewDidAppear(_ animated: Bool) {
        wf_viewDidAppear(animated) // calls the original implementation (swapped)
        UIKitCapture.handle(self)
    }
}
#endif
