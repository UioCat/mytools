import CoreGraphics
import XCTest
@testable import MacToolsCore

final class ScreenshotAnnotationTests: XCTestCase {
    func testAnnotationStoreUndoesLatestMosaicOnly() {
        var store = ScreenshotAnnotationStore()
        let arrow = ScreenshotAnnotation.arrow(start: .zero, end: CGPoint(x: 10, y: 10))
        let mosaic = ScreenshotAnnotation.mosaic(CGRect(x: 1, y: 1, width: 8, height: 8))
        store.append(arrow)
        store.append(mosaic)

        XCTAssertEqual(store.undo(), mosaic)
        XCTAssertEqual(store.annotations, [arrow])
    }
}
