import XCTest
@testable import MacToolsCore

final class SuperPanelPreviewLineLimitPolicyTests: XCTestCase {
    func testTextPanelPreviewRowsAreNotLineLimited() {
        XCTAssertNil(
            SuperPanelPreviewLineLimitPolicy.lineLimit(
                for: .text,
                row: SuperPanelPreviewRow(label: "原文", value: String(repeating: "long text ", count: 80))
            )
        )
        XCTAssertNil(
            SuperPanelPreviewLineLimitPolicy.lineLimit(
                for: .text,
                row: SuperPanelPreviewRow(label: "译文", value: String(repeating: "长文本", count: 80))
            )
        )
    }

    func testTextTransitPreviewRowsAreNotLineLimited() {
        XCTAssertNil(
            SuperPanelPreviewLineLimitPolicy.lineLimit(
                for: .textTransit,
                row: SuperPanelPreviewRow(label: "文本", value: String(repeating: "transit ", count: 80))
            )
        )
    }

    func testFileSystemPreviewKeepsCompactLimit() {
        XCTAssertEqual(
            SuperPanelPreviewLineLimitPolicy.lineLimit(
                for: .fileSystem,
                row: SuperPanelPreviewRow(label: "文件", value: "/Users/example/very/long/path")
            ),
            2
        )
    }
}
