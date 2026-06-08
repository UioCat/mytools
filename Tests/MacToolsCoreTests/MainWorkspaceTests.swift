import XCTest
@testable import MacToolsCore

final class MainWorkspaceTests: XCTestCase {
    func testSettingsIsTheDefaultMainModule() {
        XCTAssertEqual(MainToolModule.defaultModule, .settings)
        XCTAssertEqual(MainToolModule.allCases.first, .settings)
    }

    func testWorkspaceSidebarIsHiddenByDefault() {
        XCTAssertFalse(MainWorkspaceLayout.isSidebarVisibleByDefault)
    }

    func testWorkspaceModuleContentIsPinnedToTop() {
        XCTAssertEqual(MainWorkspaceLayout.moduleContentHorizontalAlignment, .leading)
        XCTAssertEqual(MainWorkspaceLayout.moduleContentVerticalAlignment, .top)
    }

    func testClipboardSearchFocusTokenAdvancesOnlyWhenOpeningClipboard() {
        XCTAssertEqual(
            ClipboardSearchFocusPolicy.focusToken(afterOpening: .settings, currentToken: 7),
            7
        )
        XCTAssertEqual(
            ClipboardSearchFocusPolicy.focusToken(afterOpening: .translation, currentToken: 7),
            7
        )
        XCTAssertEqual(
            ClipboardSearchFocusPolicy.focusToken(afterOpening: .clipboard, currentToken: 7),
            8
        )
    }

    func testCollapsedSidebarToggleKeepsFullHitTarget() {
        XCTAssertGreaterThanOrEqual(MainWorkspaceLayout.collapsedSidebarToggleSize.width, 44)
        XCTAssertGreaterThanOrEqual(MainWorkspaceLayout.collapsedSidebarToggleSize.height, 44)
    }

    func testEveryMainModuleProvidesHeaderMetadata() {
        for module in MainToolModule.allCases {
            XCTAssertFalse(module.title.isEmpty)
            XCTAssertFalse(module.subtitle.isEmpty)
            XCTAssertFalse(module.iconName.isEmpty)
        }
    }

    func testTranslationModuleHasDedicatedHeaderSubtitle() {
        XCTAssertEqual(MainToolModule.translation.subtitle, "百炼翻译与超级右键")
    }

    func testEscapeKeyMapsToDismissForEveryMainModule() {
        let resolver = PanelKeyCommandResolver()

        XCTAssertEqual(resolver.command(forKeyCode: 53), .dismiss)
        XCTAssertNil(resolver.command(forKeyCode: 36))
    }
}
