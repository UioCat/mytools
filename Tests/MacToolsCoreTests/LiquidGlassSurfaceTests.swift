import XCTest
@testable import MacToolsCore

final class LiquidGlassSurfaceTests: XCTestCase {
    func testPanelStyleUsesClearTextMaterialGlass() {
        let style = LiquidGlassSurfaceStyle.panel(cornerRadius: 30)

        XCTAssertEqual(style.cornerRadius, 30)
        XCTAssertFalse(style.isNativeGlassInteractive)
        XCTAssertFalse(style.usesNativeGlassEffect)
        XCTAssertLessThanOrEqual(style.nativeTintOpacity, 0.10)
        XCTAssertLessThanOrEqual(style.nativeBaseOpacity, 0.04)
        XCTAssertGreaterThanOrEqual(style.materialOpacity, 0.80)
        XCTAssertLessThanOrEqual(style.legacyOverlayOpacity, 0.14)
        XCTAssertGreaterThanOrEqual(style.highlightOpacity, 0.16)
        XCTAssertGreaterThanOrEqual(style.shadowOpacity, 0.20)
    }

    func testPanelStyleKeepsOuterFrameDimensional() {
        let style = LiquidGlassSurfaceStyle.panel(cornerRadius: 30)

        XCTAssertGreaterThanOrEqual(style.borderOpacity, 0.24)
        XCTAssertGreaterThanOrEqual(style.edgeDepthOpacity, 0.08)
        XCTAssertGreaterThanOrEqual(style.shadowRadius, 30)
        XCTAssertGreaterThanOrEqual(style.shadowY, 16)
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
        XCTAssertLessThanOrEqual(unselected.nativeTintOpacity, 0.08)
        XCTAssertLessThanOrEqual(selected.nativeTintOpacity, 0.14)
        XCTAssertLessThanOrEqual(selected.legacyOverlayOpacity, 0.18)
        XCTAssertGreaterThanOrEqual(selected.highlightOpacity, 0.18)
        XCTAssertLessThanOrEqual(selected.shadowOpacity, 0.22)
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
        XCTAssertLessThanOrEqual(selected.accentFocusOpacity, 0.66)
        XCTAssertLessThanOrEqual(selected.accentTintOpacity, 0.18)
    }
}
