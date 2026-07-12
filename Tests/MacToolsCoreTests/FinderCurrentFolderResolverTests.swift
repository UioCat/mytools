import Foundation
import XCTest
@testable import MacToolsCore

final class FinderCurrentFolderResolverTests: XCTestCase {
    func testFallsBackToScriptingDocumentWhenAccessibilityDocumentIsUnavailable() {
        var scriptingCallCount = 0
        let resolver = SystemFinderCurrentFolderResolver(
            desktopDirectory: URL(fileURLWithPath: "/Users/example/Desktop", isDirectory: true),
            accessibilityDocument: { _ in .unavailable },
            scriptingDocument: {
                scriptingCallCount += 1
                return "file:///Users/example/Project/"
            }
        )

        let result = resolver.currentFolderURL(processIdentifier: 42)

        XCTAssertEqual(result?.standardizedFileURL.path, "/Users/example/Project")
        XCTAssertEqual(scriptingCallCount, 1)
    }

    func testValidAccessibilityDocumentWinsWithoutCallingScriptingDocument() {
        var scriptingCallCount = 0
        let resolver = SystemFinderCurrentFolderResolver(
            desktopDirectory: URL(fileURLWithPath: "/Users/example/Desktop", isDirectory: true),
            accessibilityDocument: { _ in
                .value("file:///Users/example/Accessibility/" as CFString)
            },
            scriptingDocument: {
                scriptingCallCount += 1
                return "file:///Users/example/Scripting/"
            }
        )

        let result = resolver.currentFolderURL(processIdentifier: 42)

        XCTAssertEqual(result?.standardizedFileURL.path, "/Users/example/Accessibility")
        XCTAssertEqual(scriptingCallCount, 0)
    }

    func testNoFinderWindowReturnsDesktopWithoutCallingScriptingDocument() {
        var scriptingCallCount = 0
        let desktopDirectory = URL(
            fileURLWithPath: "/Users/example/Desktop",
            isDirectory: true
        )
        let resolver = SystemFinderCurrentFolderResolver(
            desktopDirectory: desktopDirectory,
            accessibilityDocument: { _ in .noWindow },
            scriptingDocument: {
                scriptingCallCount += 1
                return "file:///Users/example/Scripting/"
            }
        )

        let result = resolver.currentFolderURL(processIdentifier: 42)

        XCTAssertEqual(result, desktopDirectory)
        XCTAssertEqual(scriptingCallCount, 0)
    }

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
