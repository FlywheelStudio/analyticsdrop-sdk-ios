import XCTest
@testable import Wayfind

final class ScreenNameHintTests: XCTestCase {
    // MARK: hosting-controller generic parsing (SwiftUI, Mechanism A)

    func testSimpleHostingGeneric() {
        XCTAssertEqual(ScreenNameHint.fromHostingClass("UIHostingController<DetailView>"), "Detail")
    }

    func testSkipsWrapperTypes() {
        XCTAssertEqual(
            ScreenNameHint.fromHostingClass(
                "UIHostingController<ModifiedContent<PaywallView, _SafeAreaInsetsModifier>>"),
            "Paywall")
        XCTAssertEqual(
            ScreenNameHint.fromHostingClass("NavigationStackHostingController<AnyView, OrderHistoryView>"),
            "Order History")
    }

    func testStripsModuleQualification() {
        XCTAssertEqual(ScreenNameHint.fromHostingClass("UIHostingController<Primus.WorkoutDetailView>"), "Workout Detail")
    }

    func testNoUsableTypeReturnsNil() {
        XCTAssertNil(ScreenNameHint.fromHostingClass("UIHostingController<AnyView>"))
        XCTAssertNil(ScreenNameHint.fromHostingClass("UIHostingController<_TtGV7SwiftUI>"))
        XCTAssertNil(ScreenNameHint.fromHostingClass("PlainClassNoGenerics"))
    }

    func testSkipsModifierAndStyleSuffixes() {
        XCTAssertEqual(
            ScreenNameHint.fromHostingClass("UIHostingController<ModifiedContent<CardStyle, HomeView>>"),
            "Home")
    }

    // MARK: UIKit class names

    func testStripsViewControllerSuffix() {
        XCTAssertEqual(ScreenNameHint.fromUIKitClass("CheckoutViewController"), "Checkout")
        XCTAssertEqual(ScreenNameHint.fromUIKitClass("OrderHistoryViewController"), "Order History")
    }

    func testStripsVCAndControllerSuffixes() {
        XCTAssertEqual(ScreenNameHint.fromUIKitClass("PaywallVC"), "Paywall")
        XCTAssertEqual(ScreenNameHint.fromUIKitClass("SettingsController"), "Settings")
    }

    func testBareSuffixDegradesGracefully() {
        // A class literally named "ViewController" strips the Controller suffix and keeps "View".
        XCTAssertEqual(ScreenNameHint.fromUIKitClass("ViewController"), "View")
    }
}
