#if canImport(UIKit)
import UIKit
import CryptoKit

/// Mechanism C (§3.3): a structural signature of the key window's view hierarchy, hashed to a
/// stable id. Records only (depth, class, bucketed frame, hasText) — NEVER text content.
enum ScreenFingerprint {
    static func current() -> String? {
        guard let window = keyWindow() else { return nil }
        let screen = window.bounds.size
        guard screen.width > 0, screen.height > 0 else { return nil }

        var elements: [String] = []
        walk(window, depth: 0, screen: screen, into: &elements)
        guard !elements.isEmpty else { return nil }

        elements.sort()
        let digest = SHA256.hash(data: Data(elements.joined(separator: ";").utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "fp_" + String(hex.prefix(16))
    }

    private static func walk(_ view: UIView, depth: Int, screen: CGSize, into elements: inout [String]) {
        for sub in view.subviews {
            guard !sub.isHidden, sub.alpha > 0.01 else { continue }
            let size = sub.bounds.size
            if size.width >= 20, size.height >= 20 {
                let frame = sub.convert(sub.bounds, to: nil) // window coordinates
                let colW = max(screen.width / 12, 1)
                let rowH = max(screen.height / 24, 1)
                let cls = String(describing: type(of: sub))
                let bucket = "\(Int(frame.minX / colW)),\(Int(frame.minY / rowH)),\(Int(frame.width / colW)),\(Int(frame.height / rowH))"
                elements.append("\(depth)|\(cls)|\(bucket)|\(hasText(sub) ? 1 : 0)")
            }
            walk(sub, depth: depth + 1, screen: screen, into: &elements)
        }
    }

    /// Boolean only — recording actual text would violate the privacy invariant (CLAUDE.md).
    private static func hasText(_ view: UIView) -> Bool {
        if let l = view as? UILabel { return !(l.text?.isEmpty ?? true) }
        if let t = view as? UITextView { return !t.text.isEmpty }
        if let f = view as? UITextField { return !(f.text?.isEmpty ?? true) }
        return false
    }

    static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes where scene.activationState == .foregroundActive {
            if let key = scene.windows.first(where: { $0.isKeyWindow }) { return key }
            if let first = scene.windows.first { return first }
        }
        return scenes.first?.windows.first
    }
}
#endif
