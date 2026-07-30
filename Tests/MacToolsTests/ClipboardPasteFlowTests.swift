import XCTest
@testable import MacTools
@testable import MacToolsCore

final class ClipboardPasteFlowTests: XCTestCase {
    @MainActor
    func testPasteFlowCopiesBeforePermissionHideAndActivation() async {
        let events = EventRecorder()
        let flow = ClipboardPasteFlow(
            copy: { _ in events.append("copy") },
            canPostPasteEvent: {
                events.append("permission")
                return true
            },
            showPermissionAlert: { events.append("alert") },
            hidePanel: { events.append("hide") },
            activateAndPaste: { events.append("activate") },
            reportError: { _ in events.append("error") }
        )

        await flow.run(.testItem(text: "hello"))

        XCTAssertEqual(events.values, ["copy", "permission", "hide", "activate"])
    }

    @MainActor
    func testPasteFlowStopsAndReportsWhenCopyFails() async {
        let events = EventRecorder()
        let flow = ClipboardPasteFlow(
            copy: { _ in
                events.append("copy")
                throw MacToolsTestError.expectedFailure
            },
            canPostPasteEvent: {
                events.append("permission")
                return true
            },
            showPermissionAlert: { events.append("alert") },
            hidePanel: { events.append("hide") },
            activateAndPaste: { events.append("activate") },
            reportError: { _ in events.append("error") }
        )

        await flow.run(.testItem(text: "hello"))

        XCTAssertEqual(events.values, ["copy", "error"])
    }

    @MainActor
    func testPasteFlowShowsAlertWithoutHidingOrActivatingWhenPermissionIsMissing() async {
        let events = EventRecorder()
        let flow = ClipboardPasteFlow(
            copy: { _ in events.append("copy") },
            canPostPasteEvent: {
                events.append("permission")
                return false
            },
            showPermissionAlert: { events.append("alert") },
            hidePanel: { events.append("hide") },
            activateAndPaste: { events.append("activate") },
            reportError: { _ in events.append("error") }
        )

        await flow.run(.testItem(text: "hello"))

        XCTAssertEqual(events.values, ["copy", "permission", "alert"])
    }
}
