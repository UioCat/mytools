import XCTest
@testable import MacTools
@testable import MacToolsCore

final class ClipboardPasteFlowTests: XCTestCase {
    @MainActor
    func testPasteFlowCopiesBeforePermissionHideAndActivation() async {
        let events = EventRecorder()
        let flow = ClipboardPasteFlow(
            copy: { _, validateCurrent in
                try validateCurrent()
                events.append("copy")
            },
            canPostPasteEvent: {
                events.append("permission")
                return true
            },
            showPermissionAlert: { events.append("alert") },
            hidePanel: { events.append("hide") },
            reportError: { _ in events.append("error") }
        )

        let task = flow.start(
            .testItem(text: "hello"),
            target: (),
            replacing: nil,
            activateAndPaste: { _ in events.append("activate") }
        )
        await task.value

        XCTAssertEqual(events.values, ["copy", "permission", "hide", "activate"])
    }

    @MainActor
    func testPasteFlowStopsAndReportsWhenCopyFails() async {
        let events = EventRecorder()
        let flow = ClipboardPasteFlow(
            copy: { _, _ in
                events.append("copy")
                throw MacToolsTestError.expectedFailure
            },
            canPostPasteEvent: {
                events.append("permission")
                return true
            },
            showPermissionAlert: { events.append("alert") },
            hidePanel: { events.append("hide") },
            reportError: { _ in events.append("error") }
        )

        let task = flow.start(
            .testItem(text: "hello"),
            target: (),
            replacing: nil,
            activateAndPaste: { _ in events.append("activate") }
        )
        await task.value

        XCTAssertEqual(events.values, ["copy", "error"])
    }

    @MainActor
    func testPasteFlowShowsAlertWithoutHidingOrActivatingWhenPermissionIsMissing() async {
        let events = EventRecorder()
        let flow = ClipboardPasteFlow(
            copy: { _, validateCurrent in
                try validateCurrent()
                events.append("copy")
            },
            canPostPasteEvent: {
                events.append("permission")
                return false
            },
            showPermissionAlert: { events.append("alert") },
            hidePanel: { events.append("hide") },
            reportError: { _ in events.append("error") }
        )

        let task = flow.start(
            .testItem(text: "hello"),
            target: (),
            replacing: nil,
            activateAndPaste: { _ in events.append("activate") }
        )
        await task.value

        XCTAssertEqual(events.values, ["copy", "permission", "alert"])
    }

    @MainActor
    func testNewRequestCancelsOlderRequestBeforeItWritesPasteboard() async {
        let events = EventRecorder()
        let oldPrepare = ControlledSuspension()
        let flow = ClipboardPasteFlow(
            copy: { item, validateCurrent in
                let text = item.text ?? "missing"
                events.append("prepare-\(text)")
                if text == "old" {
                    await oldPrepare.suspend()
                }
                try validateCurrent()
                events.append("write-\(text)")
            },
            canPostPasteEvent: {
                events.append("permission")
                return true
            },
            showPermissionAlert: { events.append("alert") },
            hidePanel: { events.append("hide") },
            reportError: { _ in events.append("error") }
        )

        let oldTask = flow.start(
            .testItem(text: "old"),
            target: "old-target",
            replacing: nil,
            activateAndPaste: { target in events.append("activate-\(target)") }
        )
        await oldPrepare.waitUntilSuspended()
        let newTask = flow.start(
            .testItem(text: "new"),
            target: "new-target",
            replacing: oldTask,
            activateAndPaste: { target in events.append("activate-\(target)") }
        )
        await newTask.value
        await oldPrepare.resume()
        await oldTask.value

        XCTAssertEqual(
            events.values,
            [
                "prepare-old",
                "prepare-new",
                "write-new",
                "permission",
                "hide",
                "activate-new-target"
            ]
        )
    }

    @MainActor
    func testNewRequestPreventsOlderMarkedRequestFromHidingOrUsingNewTarget() async {
        let events = EventRecorder()
        let oldMarkUsed = ControlledSuspension()
        let flow = ClipboardPasteFlow(
            copy: { item, validateCurrent in
                let text = item.text ?? "missing"
                try validateCurrent()
                events.append("write-\(text)")
                if text == "old" {
                    await oldMarkUsed.suspend()
                }
            },
            canPostPasteEvent: {
                events.append("permission")
                return true
            },
            showPermissionAlert: { events.append("alert") },
            hidePanel: { events.append("hide") },
            reportError: { _ in events.append("error") }
        )

        let oldTask = flow.start(
            .testItem(text: "old"),
            target: "old-target",
            replacing: nil,
            activateAndPaste: { target in events.append("activate-\(target)") }
        )
        await oldMarkUsed.waitUntilSuspended()
        let newTask = flow.start(
            .testItem(text: "new"),
            target: "new-target",
            replacing: oldTask,
            activateAndPaste: { target in events.append("activate-\(target)") }
        )
        await newTask.value
        await oldMarkUsed.resume()
        await oldTask.value

        XCTAssertEqual(
            events.values,
            [
                "write-old",
                "write-new",
                "permission",
                "hide",
                "activate-new-target"
            ]
        )
    }
}

private actor ControlledSuspension {
    private var isSuspended = false
    private var continuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        isSuspended = true
        await withCheckedContinuation {
            continuation = $0
        }
    }

    func waitUntilSuspended() async {
        while !isSuspended {
            await Task.yield()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
