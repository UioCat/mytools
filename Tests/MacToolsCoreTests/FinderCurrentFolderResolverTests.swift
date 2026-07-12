import Foundation
import XCTest
@testable import MacToolsCore

final class FinderCurrentFolderResolverTests: XCTestCase {
    func testParsesPercentEncodedFinderDocumentURL() {
        let result = FinderDocumentURLParser.fileURL(
            from: "file:///Users/example/My%20Project/"
        )

        XCTAssertEqual(result?.path, "/Users/example/My Project")
        XCTAssertEqual(result?.isFileURL, true)
    }

    func testParsesAbsoluteFinderDocumentPath() {
        let result = FinderDocumentURLParser.fileURL(
            from: "/Users/example/Project"
        )

        XCTAssertEqual(result?.path, "/Users/example/Project")
        XCTAssertEqual(result?.isFileURL, true)
    }

    func testRejectsNonFileAndEmptyFinderDocumentValues() {
        XCTAssertNil(FinderDocumentURLParser.fileURL(from: "https://example.com"))
        XCTAssertNil(FinderDocumentURLParser.fileURL(from: "   "))
    }
}
