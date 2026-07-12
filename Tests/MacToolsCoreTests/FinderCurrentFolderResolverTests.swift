import Foundation
import XCTest
@testable import MacToolsCore

final class FinderCurrentFolderResolverTests: XCTestCase {
    func testFallsBackToScriptingDocumentWhenAccessibilityDocumentIsUnavailable() async {
        var scriptingCallCount = 0
        let resolver = SystemFinderCurrentFolderResolver(
            desktopDirectory: URL(fileURLWithPath: "/Users/example/Desktop", isDirectory: true),
            accessibilityDocument: { _ in .unavailable },
            scriptingDocument: {
                scriptingCallCount += 1
                return "file:///Users/example/Project/"
            }
        )

        let result = await resolver.currentFolderURL(processIdentifier: 42)

        XCTAssertEqual(result?.standardizedFileURL.path, "/Users/example/Project")
        XCTAssertEqual(scriptingCallCount, 1)
    }

    func testValidAccessibilityDocumentWinsWithoutCallingScriptingDocument() async {
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

        let result = await resolver.currentFolderURL(processIdentifier: 42)

        XCTAssertEqual(result?.standardizedFileURL.path, "/Users/example/Accessibility")
        XCTAssertEqual(scriptingCallCount, 0)
    }

    func testNoFinderWindowReturnsDesktopWithoutCallingScriptingDocument() async {
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

        let result = await resolver.currentFolderURL(processIdentifier: 42)

        XCTAssertEqual(result, desktopDirectory)
        XCTAssertEqual(scriptingCallCount, 0)
    }

    @MainActor
    func testSuspendingScriptingDocumentAllowsMainActorToAdvance() async {
        let scriptingStarted = expectation(description: "scripting started")
        var releaseScripting: CheckedContinuation<Void, Never>?
        var mainActorAdvanced = false
        let resolver = SystemFinderCurrentFolderResolver(
            desktopDirectory: URL(fileURLWithPath: "/Users/example/Desktop", isDirectory: true),
            accessibilityDocument: { _ in .unavailable },
            scriptingDocument: {
                scriptingStarted.fulfill()
                await withCheckedContinuation { continuation in
                    releaseScripting = continuation
                }
                return "file:///Users/example/Project/"
            }
        )

        let resolution = Task { @MainActor in
            await resolver.currentFolderURL(processIdentifier: 42)
        }
        await fulfillment(of: [scriptingStarted], timeout: 1)

        await Task { @MainActor in
            mainActorAdvanced = true
        }.value

        XCTAssertTrue(mainActorAdvanced)
        releaseScripting?.resume()
        let result = await resolution.value
        XCTAssertEqual(result?.standardizedFileURL.path, "/Users/example/Project")
    }

    func testSuccessfulEmptyFinderWindowsIsNoWindow() {
        XCTAssertEqual(
            FinderWindowLookupClassification.classify(error: .success, windowCount: 0),
            .noWindow
        )
    }

    func testCannotCompleteFinderWindowLookupIsUnavailable() {
        XCTAssertEqual(
            FinderWindowLookupClassification.classify(error: .cannotComplete, windowCount: 0),
            .unavailable
        )
    }

    func testAPIDisabledFinderWindowLookupIsUnavailable() {
        XCTAssertEqual(
            FinderWindowLookupClassification.classify(error: .apiDisabled, windowCount: 0),
            .unavailable
        )
    }

    func testSuccessfulPositiveFinderWindowCountIsAvailable() {
        XCTAssertEqual(
            FinderWindowLookupClassification.classify(error: .success, windowCount: 1),
            .available
        )
    }

    func testMissingOrInconsistentFinderWindowCountIsUnavailable() {
        XCTAssertEqual(
            FinderWindowLookupClassification.classify(error: .success, windowCount: nil),
            .unavailable
        )
        XCTAssertEqual(
            FinderWindowLookupClassification.classify(error: .success, windowCount: -1),
            .unavailable
        )
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
