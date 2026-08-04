import SwiftUI
import AnalyticsDrop

// Throwaway harness that exercises the real AnalyticsDrop SDK end-to-end: it auto-drives a
// NavigationStack journey so screen_views + edges + a purchase appear in the dashboard with
// no manual tapping. The Primus integration is the real deliverable; this just proves the loop.

@main
struct AnalyticsDropDemoApp: App {
    init() {
        AnalyticsDrop.start(
            apiKey: "ad_test_primus_dev",
            endpoint: URL(string: "http://localhost:3100")!,
            debug: true
        )
        AnalyticsDrop.identify("demo_user_1")
    }
    var body: some Scene {
        WindowGroup { RootView().analyticsDropTracked() }
    }
}

enum Screen: Hashable { case detail, paywall, checkout }

struct RootView: View {
    @State private var path: [Screen] = []
    var body: some View {
        NavigationStack(path: $path) {
            HomeScreen()
                .navigationDestination(for: Screen.self) { screen in
                    switch screen {
                    case .detail: DetailScreen()
                    case .paywall: PaywallScreen()
                    case .checkout: CheckoutScreen()
                    }
                }
        }
        .task { await autoDrive() }
    }

    // Simulate a user journey: Home -> Detail -> Paywall -> Checkout -> purchase.
    private func autoDrive() async {
        await sleep(1.4); path = [.detail]
        await sleep(1.6); path = [.detail, .paywall]
        await sleep(1.6); path = [.detail, .paywall, .checkout]
        await sleep(1.2); AnalyticsDrop.track("purchase", properties: ["value": 9.99, "plan": "pro"])
        // pop back home and revisit detail to create a returning-style edge
        await sleep(1.2); path = []
        await sleep(1.2); path = [.detail]
    }

    private func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

// Distinct layouts so each screen produces a distinct structural fingerprint.

struct HomeScreen: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Home").font(.largeTitle).bold()
            Image(systemName: "house.fill").font(.system(size: 72))
            ForEach(0..<3, id: \.self) { i in
                HStack { Image(systemName: "star"); Text("Featured item \(i + 1)") }
                    .padding().frame(maxWidth: .infinity)
                    .background(.gray.opacity(0.15)).cornerRadius(12)
            }
            Spacer()
        }.padding()
    }
}

struct DetailScreen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Detail").font(.largeTitle).bold()
            Image(systemName: "doc.text.fill").font(.system(size: 96))
            Text("A detailed description spanning a couple of lines of content.")
            Spacer()
        }.padding()
    }
}

struct PaywallScreen: View {
    var body: some View {
        VStack(spacing: 28) {
            Text("Go Pro").font(.largeTitle).bold()
            Image(systemName: "crown.fill").font(.system(size: 110))
            Text("Unlock everything for $9.99/mo")
            Button("Subscribe") {}.buttonStyle(.borderedProminent).controlSize(.large)
            Spacer()
        }.padding()
    }
}

struct CheckoutScreen: View {
    var body: some View {
        Form {
            Section("Payment") {
                Text("Card •••• 4242")
                Text("Total: $9.99")
            }
            Section { Button("Pay now") {} }
        }
    }
}
