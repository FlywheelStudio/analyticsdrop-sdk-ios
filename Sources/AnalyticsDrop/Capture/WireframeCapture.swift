#if canImport(UIKit)
import UIKit

/// UIKit side of the wireframe pipeline (see Wireframe.swift for the pure planner and the
/// privacy note). Walks the key window's **layer tree** — on modern iOS, SwiftUI renders a whole
/// screen as sublayers of one hosting view (text as `CGDrawingLayer`, images as `ImageLayer`,
/// colored blocks as plain `CALayer`s), so a view walk sees almost nothing. Records geometry,
/// colors and coarse roles — deliberately never text content, input values or image pixels —
/// then rasterizes the plan to a base64 PNG.
enum WireframeCapture {
    /// Pixel budget for the rendered PNG (D22: 400×866 for a portrait phone).
    private static let maxWidth: CGFloat = 400
    private static let maxHeight: CGFloat = 866
    private static let maxFacts = 600
    private static let maxDepth = 48
    /// Well under the server's 700KB cap — a wireframe PNG is typically 5–40KB.
    static let maxBase64Length = 256_000

    /// Render the current key window as a redacted wireframe. Main thread only.
    /// Returns base64 PNG (no data-URL prefix), or nil when there is nothing useful to draw
    /// or the result would exceed `maxBase64Length`.
    static func capturePng() -> String? {
        guard let window = ScreenFingerprint.keyWindow() else { return nil }
        let size = window.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }

        var facts: [WireElementFact] = []
        walk(window.layer, root: window.layer, depth: 0, into: &facts)

        let pageBg = wireColor(window.backgroundColor?.cgColor)
            ?? wireColor(UIColor.systemBackground.resolvedColor(with: window.traitCollection).cgColor)
        guard let plan = Wireframe.plan(facts: facts, size: size, pageBg: pageBg),
              plan.commands.count >= 2 else { return nil }

        guard let png = renderPng(plan) else { return nil }
        let base64 = png.base64EncodedString()
        return base64.count <= maxBase64Length ? base64 : nil
    }

    // MARK: - Collect

    private static func walk(_ layer: CALayer, root: CALayer, depth: Int, into facts: inout [WireElementFact]) {
        guard depth <= maxDepth else { return }
        for sub in layer.sublayers ?? [] {
            if facts.count >= maxFacts { return }
            guard !sub.isHidden, sub.opacity > 0.01 else { continue }
            // A hidden/transparent view hides its whole layer subtree.
            if let view = sub.delegate as? UIView, view.isHidden || view.alpha <= 0.01 { continue }
            if let fact = classify(sub, root: root, depth: depth) { facts.append(fact) }
            walk(sub, root: root, depth: depth + 1, into: &facts)
        }
    }

    /// Role + color of one layer. When the layer backs a UIView the view types give the role;
    /// otherwise the layer class does (SwiftUI's private render layers). Text content is reduced
    /// to a line count; image pixels are never read (the planner paints a constant neutral).
    private static func classify(_ layer: CALayer, root: CALayer, depth: Int) -> WireElementFact? {
        let size = layer.bounds.size
        guard size.width >= Wireframe.minSize, size.height >= Wireframe.minSize else { return nil }
        let frame = layer.convert(layer.bounds, to: root)
        let radius = layer.cornerRadius
        let bg = wireColor(layer.backgroundColor)

        if let view = layer.delegate as? UIView, view.layer === layer {
            if let label = view as? UILabel, !(label.text?.isEmpty ?? true) {
                return textFact(depth: depth, frame: frame, radius: radius,
                                lineHeight: max(label.font?.lineHeight ?? 17, 1), color: label.textColor)
            }
            if let tv = view as? UITextView, !tv.text.isEmpty {
                return textFact(depth: depth, frame: frame, radius: radius,
                                lineHeight: max(tv.font?.lineHeight ?? 17, 1), color: tv.textColor)
            }
            if view is UITextField {
                // Never distinguish filled from empty (that leaks state); a field is a control.
                return WireElementFact(depth: depth, frame: frame, radius: radius, kind: .control, fill: bg)
            }
            if view is UIImageView {
                return WireElementFact(depth: depth, frame: frame, radius: radius, kind: .image)
            }
            if view is UIControl {
                return WireElementFact(depth: depth, frame: frame, radius: radius, kind: .control, fill: bg)
            }
            if let bg, bg.a > 0 {
                return WireElementFact(depth: depth, frame: frame, radius: radius, kind: .block, fill: bg)
            }
            return nil
        }

        // Pure render layers (SwiftUI internals). Class names are the only signal; the drawn
        // pixels are never read.
        let className = String(describing: type(of: layer))
        if className.contains("CGDrawing") {
            // SwiftUI Text draws its glyphs into this layer. Fixed-pattern bars, gray fallback
            // color (reading the real color would mean sampling rendered pixels — never done).
            return textFact(depth: depth, frame: frame, radius: radius, lineHeight: 20, color: nil)
        }
        if layer.contents != nil || className.contains("ImageLayer") || className.contains("ColorShape") {
            return WireElementFact(depth: depth, frame: frame, radius: radius, kind: .image)
        }
        if let bg, bg.a > 0 {
            return WireElementFact(depth: depth, frame: frame, radius: radius, kind: .block, fill: bg)
        }
        return nil
    }

    private static func textFact(depth: Int, frame: CGRect, radius: CGFloat,
                                 lineHeight: CGFloat, color: UIColor?) -> WireElementFact {
        let lines = max(1, Int((frame.height / lineHeight).rounded()))
        return WireElementFact(depth: depth, frame: frame, radius: radius, kind: .text,
                               lines: lines, textColor: wireColor(color?.cgColor))
    }

    /// CGColor → clamped sRGB components. Anything unconvertible is dropped, so no
    /// app-controlled value other than four numbers can influence the plan.
    private static func wireColor(_ cgColor: CGColor?) -> WireColor? {
        guard let cgColor else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(cgColor: cgColor).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        guard a > 0 else { return nil }
        return WireColor(r: r, g: g, b: b, a: a)
    }

    // MARK: - Render

    /// Rasterize a plan, scaled to fit 400×866. Pure CoreGraphics drawing of our own rects —
    /// safe off the main thread (UIGraphicsImageRenderer is thread-safe).
    static func renderPng(_ plan: WireframePlan) -> Data? {
        let scale = min(maxWidth / plan.size.width, maxHeight / plan.size.height, 3)
        let canvas = CGSize(width: max(1, (plan.size.width * scale).rounded()),
                            height: max(1, (plan.size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        let image = renderer.image { ctx in
            ctx.cgContext.scaleBy(x: scale, y: scale)
            for c in plan.commands {
                let path = UIBezierPath(
                    roundedRect: c.rect,
                    cornerRadius: min(c.radius, min(c.rect.width, c.rect.height) / 2)
                )
                ctx.cgContext.setFillColor(red: c.fill.r, green: c.fill.g, blue: c.fill.b, alpha: c.fill.a)
                ctx.cgContext.addPath(path.cgPath)
                ctx.cgContext.fillPath()
            }
        }
        return image.pngData()
    }
}
#endif
