import XCTest
@testable import MacToolsCore

final class LiquidGlassSurfaceTests: XCTestCase {
    func testControlMetricsDefineTheApprovedSemanticButtonSizes() {
        XCTAssertEqual(MacToolsControlMetrics.textActionHeight, 40)
        XCTAssertEqual(MacToolsControlMetrics.inlineIconSize, CGSize(width: 32, height: 32))
        XCTAssertEqual(MacToolsControlMetrics.toolbarIconSize, CGSize(width: 40, height: 40))
        XCTAssertEqual(MacToolsControlMetrics.sidebarNavigationHeight, 44)
        XCTAssertEqual(MacToolsControlMetrics.clipboardCategoryHeight, 36)
        XCTAssertEqual(MacToolsControlMetrics.clipboardCategoryMinimumWidth, 96)
        XCTAssertEqual(MacToolsControlMetrics.superPanelActionRowHeight, 56)
        XCTAssertEqual(MacToolsControlMetrics.windowLayoutButtonHeight, 40)
        XCTAssertEqual(MacToolsControlMetrics.settingsRowButtonMinimumHeight, 44)
    }

    func testPanelStyleUsesUntintedSystemGlassLikeSpotlight() {
        let style = LiquidGlassSurfaceStyle.panel(cornerRadius: 30)

        XCTAssertEqual(style.cornerRadius, 30)
        XCTAssertEqual(style.cornerShape, .fixed(30))
        XCTAssertFalse(style.isInteractive)
        XCTAssertEqual(style.tint, .none)
    }

    func testSelectedClipboardRowUsesInteractiveFrostTintAndConcentricGeometry() {
        let selectedRow = LiquidGlassSurfaceStyle.concentricModule(
            minimumCornerRadius: LiquidGlassCornerGeometry.selectedRowMinimumRadius,
            isSelected: true
        )

        XCTAssertEqual(LiquidGlassCornerGeometry.windowRadius, 40)
        XCTAssertEqual(selectedRow.cornerShape, .concentric(minimum: 18))
        XCTAssertEqual(selectedRow.tint, .frost(0.22))
        XCTAssertTrue(selectedRow.isInteractive)
    }

    func testFloatingSelectionUsesProminentSelectionTintWithPointerResponse() {
        let selection = LiquidGlassSurfaceStyle.floatingSelection(cornerRadius: 12)

        XCTAssertEqual(selection.cornerShape, .fixed(12))
        XCTAssertEqual(selection.tint, .selection(0.12))
        XCTAssertTrue(selection.isInteractive)
    }

    func testMainWorkspaceOpensAtTwoThirdsOfPreviousSize() {
        let frame = LiquidGlassWindowPanelFrame.mainWorkspace

        XCTAssertEqual(frame.idealWidth, 720)
        XCTAssertEqual(frame.idealHeight, 480)
        XCTAssertEqual(frame.minWidth, 600)
        XCTAssertEqual(frame.minHeight, 414)
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

    func testIdentityStylePreservesGlassNodeWithoutDrawingASurface() {
        let identity = LiquidGlassSurfaceStyle.identity(cornerRadius: 14)

        XCTAssertEqual(identity.cornerShape, .fixed(14))
        XCTAssertFalse(identity.isInteractive)
        XCTAssertTrue(identity.usesIdentityEffect)
        XCTAssertEqual(identity.effect, .identity)
    }

    func testChipStyleStaysLightweightAndStatic() {
        let chip = LiquidGlassSurfaceStyle.chip(cornerRadius: 10)

        XCTAssertFalse(chip.isInteractive)
        XCTAssertEqual(chip.tint, .accent(0.08))
    }
}
