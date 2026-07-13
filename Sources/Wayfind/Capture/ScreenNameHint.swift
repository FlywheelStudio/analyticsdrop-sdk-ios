/// Derives human-readable screen-name hints from *code identifiers only* — class names and
/// generic type parameters. Deliberately never from view content or `navigationItem.title`:
/// titles can carry user data ("My Playlist"), which would violate the privacy invariant
/// (CLAUDE.md). Hints ride on `screen.name` in the wire format; the backend seeds
/// `display_name` with the first hint, and dashboard renames always win.
enum ScreenNameHint {
    /// SwiftUI wrapper/plumbing types that never identify a screen.
    private static let skip: Set<String> = [
        "ModifiedContent", "AnyView", "TupleView", "Optional", "Group",
        "NavigationStack", "NavigationView", "NavigationSplitView", "TabView",
        "ForEach", "List", "ScrollView", "VStack", "HStack", "ZStack",
        "EquatableView", "ID", "RootModifier", "ContentView",
    ]
    private static let skipSuffixes = ["Modifier", "Style", "Configuration", "Key"]

    /// `"UIHostingController<ModifiedContent<DetailView, _SafeAreaModifier>>"` → `"Detail"`.
    /// Returns nil when no app-looking type appears in the generic parameters.
    static func fromHostingClass(_ typeDescription: String) -> String? {
        guard let lt = typeDescription.firstIndex(of: "<") else { return nil }
        let inner = typeDescription[typeDescription.index(after: lt)...]
        for raw in inner.split(whereSeparator: { "<>, ()".contains($0) }) {
            // Strip module qualification: "MyApp.DetailView" -> "DetailView".
            let token = raw.split(separator: ".").last.map(String.init) ?? String(raw)
            guard let first = token.first, first.isUppercase else { continue }
            if token.hasPrefix("_") || skip.contains(token) { continue }
            if skipSuffixes.contains(where: { token.hasSuffix($0) }) { continue }
            return prettify(token)
        }
        return nil
    }

    /// `"CheckoutViewController"` → `"Checkout"`; `"OrderHistoryVC"` → `"Order History"`.
    static func fromUIKitClass(_ className: String) -> String? {
        var name = className
        for suffix in ["ViewController", "Controller", "VC"]
        where name.hasSuffix(suffix) && name.count > suffix.count {
            name = String(name.dropLast(suffix.count))
            break
        }
        return prettify(name)
    }

    /// Drop a trailing "View", then split camel case: `"OrderHistoryView"` → `"Order History"`.
    private static func prettify(_ typeName: String) -> String? {
        var n = typeName
        if n.hasSuffix("View"), n.count > 4 { n = String(n.dropLast(4)) }
        guard !n.isEmpty else { return nil }
        var out = ""
        for ch in n {
            if ch.isUppercase, let last = out.last, last.isLowercase { out.append(" ") }
            out.append(ch)
        }
        return out
    }
}
