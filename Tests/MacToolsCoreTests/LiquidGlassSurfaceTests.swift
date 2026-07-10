import XCTest
@testable import MacToolsCore

final class LiquidGlassSurfaceTests: XCTestCase {
    func testPanelStyleUsesNeutralStaticGlass() {
        let style = LiquidGlassSurfaceStyle.panel(cornerRadius: 30)

        XCTAssertEqual(style.cornerRadius, 30)
        XCTAssertEqual(style.cornerShape, .fixed(30))
        XCTAssertFalse(style.isInteractive)
        XCTAssertEqual(style.tint, .neutral(0.28))
    }

    func testWindowAndSelectedRowUseSystemConcentricCornerGeometry() {
        let selectedRow = LiquidGlassSurfaceStyle.concentricModule(
            minimumCornerRadius: LiquidGlassCornerGeometry.selectedRowMinimumRadius,
            isSelected: true
        )

        XCTAssertEqual(LiquidGlassCornerGeometry.windowRadius, 40)
        XCTAssertEqual(selectedRow.cornerShape, .concentric(minimum: 18))
        XCTAssertEqual(selectedRow.tint, .neutral(0.32))
        XCTAssertFalse(selectedRow.isInteractive)
    }

    func testWindowPanelSurfaceIsAppliedAfterSizingToAvoidTransparentOuterAppArea() {
        let frame = LiquidGlassWindowPanelFrame.mainWorkspace

        XCTAssertEqual(frame.surfacePlacement, .afterSizing)
        XCTAssertEqual(frame.alignment, .topLeading)
        XCTAssertEqual(frame.maxWidth, .infinity)
        XCTAssertEqual(frame.maxHeight, .infinity)
    }

    func testStaticModuleUsesStrongerTintWhenSelectedWithoutBecomingInteractive() {
        let unselected = LiquidGlassSurfaceStyle.module(cornerRadius: 20, isSelected: false)
        let selected = LiquidGlassSurfaceStyle.module(cornerRadius: 20, isSelected: true)

        XCTAssertEqual(unselected.cornerRadius, selected.cornerRadius)
        XCTAssertFalse(unselected.isInteractive)
        XCTAssertFalse(selected.isInteractive)
        XCTAssertEqual(unselected.tint, .neutral(0.10))
        XCTAssertEqual(selected.tint, .neutral(0.32))
    }

    func testInteractiveModuleKeepsPointerResponseForControls() {
        let unselected = LiquidGlassSurfaceStyle.interactiveModule(cornerRadius: 20, isSelected: false)
        let selected = LiquidGlassSurfaceStyle.interactiveModule(cornerRadius: 20, isSelected: true)

        XCTAssertTrue(unselected.isInteractive)
        XCTAssertTrue(selected.isInteractive)
        XCTAssertEqual(unselected.tint, .neutral(0.14))
        XCTAssertEqual(selected.tint, .accent(0.30))
    }

    func testChipStyleStaysLightweightAndStatic() {
        let chip = LiquidGlassSurfaceStyle.chip(cornerRadius: 10)

        XCTAssertFalse(chip.isInteractive)
        XCTAssertEqual(chip.tint, .accent(0.08))
    }
}
