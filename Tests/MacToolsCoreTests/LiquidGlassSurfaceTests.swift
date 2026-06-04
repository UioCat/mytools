import XCTest
@testable import MacToolsCore

final class LiquidGlassSurfaceTests: XCTestCase {
    func testPanelStylePrefersNativeInteractiveGlass() {
        let style = LiquidGlassSurfaceStyle.panel(cornerRadius: 30)

        XCTAssertEqual(style.cornerRadius, 30)
        XCTAssertTrue(style.isNativeGlassInteractive)
        XCTAssertEqual(style.nativeTintOpacity, 0.06)
        XCTAssertLessThan(style.legacyOverlayOpacity, 0.24)
    }

    func testSelectedModuleUsesStrongerGlassThanUnselectedModule() {
        let unselected = LiquidGlassSurfaceStyle.module(cornerRadius: 20, isSelected: false)
        let selected = LiquidGlassSurfaceStyle.module(cornerRadius: 20, isSelected: true)

        XCTAssertEqual(unselected.cornerRadius, selected.cornerRadius)
        XCTAssertTrue(selected.isNativeGlassInteractive)
        XCTAssertGreaterThan(selected.nativeTintOpacity, unselected.nativeTintOpacity)
        XCTAssertGreaterThan(selected.borderOpacity, unselected.borderOpacity)
    }
}
