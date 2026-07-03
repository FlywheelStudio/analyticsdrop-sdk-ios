#if canImport(SwiftUI)
import SwiftUI

public extension View {
    /// Attach once at the SwiftUI root:
    /// `WindowGroup { ContentView().wayfindTracked() }`
    ///
    /// For the POC this is a light passthrough — automatic screen capture is driven by the
    /// `UIViewController.viewDidAppear` swizzle, which fires for the `UIHostingController`s that back
    /// SwiftUI's `NavigationStack` pushes, sheets, and `TabView` switches. Kept as the documented
    /// one-line integration point and a home for richer navigation observation later (Mechanism A).
    func wayfindTracked() -> some View { self }

    /// Escape hatch for exact naming of a specific SwiftUI screen (mirrors `Wayfind.setScreenName`).
    /// `SomeView().wayfindScreen("Checkout")`
    func wayfindScreen(_ name: String) -> some View {
        onAppear { Wayfind.setScreenName(name) }
    }
}
#endif
