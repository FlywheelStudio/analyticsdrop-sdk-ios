import Foundation
import CoreGraphics

// Colored wireframe thumbnails — the one-time screen "reference render" (DECISIONS D22).
//
// The pipeline is split so the interesting logic is pure and testable with `swift test` on macOS:
//
//   WireframeCapture.collectFacts  (UIKit-only view walk — geometry, colors, roles)
//     → Wireframe.plan             (pure: facts → rounded-rect draw commands)
//     → WireframeCapture.renderPng (UIKit-only: commands → bitmap → base64 PNG)
//
// Privacy invariant (CLAUDE.md): the draw-command vocabulary is rounded rectangles ONLY — this
// module has no text-drawing operation, so OCR-able text cannot appear in a thumbnail by
// construction. Text becomes fixed-pattern bars, images become a constant neutral block (never
// sampled), and colors travel as clamped numeric components — no string from the app can reach
// the canvas. Mirrors `SDK/web/src/wireframe.ts` in the monorepo.

/// A color as clamped numeric components. The only way app-derived color reaches a plan.
struct WireColor: Equatable {
    let r: Double
    let g: Double
    let b: Double
    let a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = min(max(r, 0), 1)
        self.g = min(max(g, 0), 1)
        self.b = min(max(b, 0), 1)
        self.a = min(max(a, 0), 1)
    }

    func withAlpha(_ alpha: Double) -> WireColor {
        WireColor(r: r, g: g, b: b, a: alpha)
    }
}

/// Coarse role of one visible element. Determines how the planner draws it.
enum WireFactKind {
    case block
    case text
    case image
    case control
}

/// One visible element, as observed by the collector. Carries no text content.
struct WireElementFact {
    let depth: Int
    /// Frame in window coordinates (points).
    let frame: CGRect
    /// Corner radius in points.
    let radius: CGFloat
    let kind: WireFactKind
    /// Background color; nil means transparent (block facts with nil fill are skipped).
    let fill: WireColor?
    /// text only: approximate rendered line count.
    let lines: Int
    /// text only: text color for the (faded) bars.
    let textColor: WireColor?

    init(depth: Int, frame: CGRect, radius: CGFloat, kind: WireFactKind,
         fill: WireColor? = nil, lines: Int = 1, textColor: WireColor? = nil) {
        self.depth = depth
        self.frame = frame
        self.radius = radius
        self.kind = kind
        self.fill = fill
        self.lines = lines
        self.textColor = textColor
    }
}

/// The only draw primitive. No text op exists — see privacy note above.
struct WireRectCommand: Equatable {
    let rect: CGRect
    let radius: CGFloat
    let fill: WireColor
}

struct WireframePlan {
    let size: CGSize
    let commands: [WireRectCommand]
}

/// Pure planner: element facts → rounded-rect commands on a canvas of the screen's size.
/// Deterministic — identical input always yields an identical plan.
enum Wireframe {
    /// Mirrors the fingerprint walk's ≥20×20pt rule (spec §3.3): smaller boxes are noise.
    static let minSize: CGFloat = 20
    static let maxTextBars = 8
    static let maxCommands = 1200
    /// Deterministic bar-width cycle — derived from position only, never from content.
    static let barWidths: [CGFloat] = [0.9, 0.6, 0.8, 0.72, 0.5]
    static let textBarAlpha = 0.45

    static let pageFallback = WireColor(r: 1, g: 1, b: 1)
    /// Neutral slate for images — deliberately constant, never sampled from pixels.
    static let imageFill = WireColor(r: 203 / 255, g: 213 / 255, b: 225 / 255)
    static let controlFill = WireColor(r: 226 / 255, g: 232 / 255, b: 240 / 255)
    static let textFallback = WireColor(r: 100 / 255, g: 116 / 255, b: 139 / 255)

    static func plan(facts: [WireElementFact], size: CGSize, pageBg: WireColor?) -> WireframePlan? {
        guard size.width > 0, size.height > 0 else { return nil }

        var commands: [WireRectCommand] = [
            WireRectCommand(rect: CGRect(origin: .zero, size: size), radius: 0, fill: pageBg ?? pageFallback),
        ]

        // Paint in depth order; the sort is stable in Swift 5, so walk order breaks ties.
        let ordered = facts.enumerated().sorted { a, b in
            a.element.depth != b.element.depth ? a.element.depth < b.element.depth : a.offset < b.offset
        }.map(\.element)

        for f in ordered {
            if commands.count >= maxCommands { break }

            // Clamp to the canvas, then apply the min-size rule to the visible part.
            let x = max(0, f.frame.minX)
            let y = max(0, f.frame.minY)
            let w = min(f.frame.maxX, size.width) - x
            let h = min(f.frame.maxY, size.height) - y
            if w < minSize || h < minSize { continue }

            let radius = f.radius.isFinite ? max(0, min(f.radius, min(w, h) / 2)) : 0
            let rect = CGRect(x: x, y: y, width: w, height: h)

            switch f.kind {
            case .image:
                commands.append(WireRectCommand(rect: rect, radius: radius, fill: imageFill))
            case .control:
                commands.append(WireRectCommand(rect: rect, radius: max(radius, 6), fill: f.fill ?? controlFill))
            case .block:
                guard let fill = f.fill, fill.a > 0 else { continue }
                commands.append(WireRectCommand(rect: rect, radius: radius, fill: fill))
            case .text:
                let lines = max(1, min(f.lines, maxTextBars))
                let slotH = h / CGFloat(lines)
                let barH = min(max(slotH * 0.5, 2), 14)
                if barH < 2 { continue }
                let base = f.textColor ?? textFallback
                let fill = base.withAlpha(base.a * textBarAlpha)
                for i in 0..<lines where commands.count < maxCommands {
                    let barW = w * barWidths[i % barWidths.count]
                    if barW < 4 { continue }
                    let barY = y + CGFloat(i) * slotH + (slotH - barH) / 2
                    commands.append(WireRectCommand(
                        rect: CGRect(x: x, y: barY, width: barW, height: barH),
                        radius: barH / 2,
                        fill: fill
                    ))
                }
            }
        }

        return WireframePlan(size: size, commands: commands)
    }
}
