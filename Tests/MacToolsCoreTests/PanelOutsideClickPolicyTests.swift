import CoreGraphics
import XCTest
@testable import MacToolsCore

final class PanelOutsideClickPolicyTests: XCTestCase {
    func testKeepsPanelForClicksInsidePanelFrame() {
        let frame = CGRect(x: 100, y: 100, width: 320, height: 240)

        XCTAssertFalse(
            PanelOutsideClickPolicy.shouldDismiss(
                panelFrame: frame,
                eventScreenLocation: CGPoint(x: 180, y: 180)
            )
        )
    }

    func testDismissesPanelForClicksOutsidePanelFrame() {
        let frame = CGRect(x: 100, y: 100, width: 320, height: 240)

        XCTAssertTrue(
            PanelOutsideClickPolicy.shouldDismiss(
                panelFrame: frame,
                eventScreenLocation: CGPoint(x: 80, y: 180)
            )
        )
    }
}
