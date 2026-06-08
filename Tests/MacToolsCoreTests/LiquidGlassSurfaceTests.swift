import XCTest
@testable import MacToolsCore

final class LiquidGlassSurfaceTests: XCTestCase {
    func testPanelStyleUsesStaticNativeGlass() {
        let style = LiquidGlassSurfaceStyle.panel(cornerRadius: 30)

        XCTAssertEqual(style.cornerRadius, 30)
        XCTAssertFalse(style.isNativeGlassInteractive)
        XCTAssertFalse(style.usesNativeGlassEffect)
        XCTAssertLessThanOrEqual(style.nativeTintOpacity, 0.025)
        XCTAssertLessThanOrEqual(style.nativeBaseOpacity, 0.015)
        XCTAssertLessThanOrEqual(style.materialOpacity, 0.78)
        XCTAssertLessThanOrEqual(style.legacyOverlayOpacity, 0.08)
        XCTAssertLessThanOrEqual(style.highlightOpacity, 0.08)
        XCTAssertLessThanOrEqual(style.shadowOpacity, 0.18)
    }

    func testPanelStyleKeepsOuterFrameTransparentAndDimensional() {
        let style = LiquidGlassSurfaceStyle.panel(cornerRadius: 30)

        XCTAssertLessThanOrEqual(style.legacyOverlayOpacity, 0.035)
        XCTAssertGreaterThanOrEqual(style.borderOpacity, 0.24)
        XCTAssertGreaterThanOrEqual(style.edgeDepthOpacity, 0.12)
        XCTAssertGreaterThanOrEqual(style.shadowRadius, 22)
        XCTAssertGreaterThanOrEqual(style.shadowY, 10)
    }

    func testWindowPanelSurfaceIsAppliedAfterSizingToAvoidTransparentOuterAppArea() {
        let frame = LiquidGlassWindowPanelFrame.mainWorkspace

        XCTAssertEqual(frame.surfacePlacement, .afterSizing)
        XCTAssertEqual(frame.alignment, .topLeading)
        XCTAssertEqual(frame.maxWidth, .infinity)
        XCTAssertEqual(frame.maxHeight, .infinity)
    }

    func testStaticModuleUsesStrongerGlassWhenSelectedWithoutBecomingInteractive() {
        let unselected = LiquidGlassSurfaceStyle.module(cornerRadius: 20, isSelected: false)
        let selected = LiquidGlassSurfaceStyle.module(cornerRadius: 20, isSelected: true)

        XCTAssertEqual(unselected.cornerRadius, selected.cornerRadius)
        XCTAssertFalse(unselected.isNativeGlassInteractive)
        XCTAssertFalse(selected.isNativeGlassInteractive)
        XCTAssertFalse(unselected.usesNativeGlassEffect)
        XCTAssertFalse(selected.usesNativeGlassEffect)
        XCTAssertGreaterThan(selected.nativeTintOpacity, unselected.nativeTintOpacity)
        XCTAssertGreaterThan(selected.borderOpacity, unselected.borderOpacity)
        XCTAssertLessThanOrEqual(unselected.nativeTintOpacity, 0.035)
        XCTAssertLessThanOrEqual(selected.nativeTintOpacity, 0.07)
        XCTAssertLessThanOrEqual(selected.legacyOverlayOpacity, 0.13)
        XCTAssertLessThanOrEqual(selected.highlightOpacity, 0.12)
        XCTAssertLessThanOrEqual(selected.shadowOpacity, 0.16)
    }

    func testInteractiveModuleKeepsPointerResponseForControls() {
        let unselected = LiquidGlassSurfaceStyle.interactiveModule(cornerRadius: 20, isSelected: false)
        let selected = LiquidGlassSurfaceStyle.interactiveModule(cornerRadius: 20, isSelected: true)

        XCTAssertTrue(unselected.isNativeGlassInteractive)
        XCTAssertTrue(selected.isNativeGlassInteractive)
        XCTAssertFalse(unselected.usesNativeGlassEffect)
        XCTAssertFalse(selected.usesNativeGlassEffect)
        XCTAssertGreaterThan(selected.accentFocusOpacity, unselected.accentFocusOpacity)
    }

    func testChipStyleStaysLightweightAndStatic() {
        let chip = LiquidGlassSurfaceStyle.chip(cornerRadius: 10)
        let module = LiquidGlassSurfaceStyle.module(cornerRadius: 20, isSelected: false)

        XCTAssertFalse(chip.isNativeGlassInteractive)
        XCTAssertFalse(chip.usesNativeGlassEffect)
        XCTAssertLessThan(chip.shadowRadius, module.shadowRadius)
        XCTAssertLessThan(chip.borderOpacity, module.borderOpacity)
    }

    func testSelectedModuleUsesAccentFocusRing() {
        let unselected = LiquidGlassSurfaceStyle.module(cornerRadius: 20, isSelected: false)
        let selected = LiquidGlassSurfaceStyle.module(cornerRadius: 20, isSelected: true)

        XCTAssertEqual(unselected.accentFocusOpacity, 0)
        XCTAssertGreaterThan(selected.accentFocusOpacity, 0)
        XCTAssertGreaterThan(selected.accentTintOpacity, unselected.accentTintOpacity)
        XCTAssertLessThanOrEqual(selected.accentFocusOpacity, 0.26)
        XCTAssertLessThanOrEqual(selected.accentTintOpacity, 0.055)
    }
}
