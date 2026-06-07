import CoreGraphics
import XCTest
@testable import MacToolsCore

final class WindowLayoutCalculatorTests: XCTestCase {
    func testCalculatesBuiltInLayoutFramesWithinVisibleFrame() {
        let visibleFrame = CGRect(x: 100, y: 50, width: 1_200, height: 800)

        XCTAssertEqual(
            WindowLayoutCalculator.targetFrame(for: .leftHalf, in: visibleFrame),
            CGRect(x: 100, y: 50, width: 600, height: 800)
        )
        XCTAssertEqual(
            WindowLayoutCalculator.targetFrame(for: .rightHalf, in: visibleFrame),
            CGRect(x: 700, y: 50, width: 600, height: 800)
        )
        XCTAssertEqual(
            WindowLayoutCalculator.targetFrame(for: .leftThird, in: visibleFrame),
            CGRect(x: 100, y: 50, width: 400, height: 800)
        )
        XCTAssertEqual(
            WindowLayoutCalculator.targetFrame(for: .rightThird, in: visibleFrame),
            CGRect(x: 900, y: 50, width: 400, height: 800)
        )
        XCTAssertEqual(
            WindowLayoutCalculator.targetFrame(for: .leftTwoThirds, in: visibleFrame),
            CGRect(x: 100, y: 50, width: 800, height: 800)
        )
        XCTAssertEqual(
            WindowLayoutCalculator.targetFrame(for: .rightTwoThirds, in: visibleFrame),
            CGRect(x: 500, y: 50, width: 800, height: 800)
        )
        XCTAssertEqual(
            WindowLayoutCalculator.targetFrame(for: .centered, in: visibleFrame),
            CGRect(x: 220, y: 130, width: 960, height: 640)
        )
        XCTAssertEqual(
            WindowLayoutCalculator.targetFrame(for: .maximize, in: visibleFrame),
            visibleFrame
        )
    }

    func testCombinationButtonCyclesThroughModes() {
        let button = WindowLayoutButton(
            id: "custom.left-right",
            title: "左右半屏",
            modes: [.leftHalf, .rightHalf]
        )

        XCTAssertEqual(button.mode(after: nil), .leftHalf)
        XCTAssertEqual(button.mode(after: .leftHalf), .rightHalf)
        XCTAssertEqual(button.mode(after: .rightHalf), .leftHalf)
        XCTAssertEqual(button.mode(after: .centered), .leftHalf)
    }

    func testWindowLayoutShortcutsAreNormalizedByModeOrder() {
        let settings = WindowLayoutSettings(
            isEnabled: true,
            modeShortcuts: [
                WindowLayoutModeShortcuts(
                    mode: .rightHalf,
                    shortcuts: [HotKeyBinding(key: "Right", modifiers: ["Command", "Option"])]
                ),
                WindowLayoutModeShortcuts(
                    mode: .leftHalf,
                    shortcuts: [
                        HotKeyBinding(key: "Left", modifiers: ["Option", "Command"]),
                        HotKeyBinding(key: "Left", modifiers: ["Option", "Command"])
                    ]
                )
            ]
        )

        XCTAssertEqual(settings.modeShortcuts.map(\.mode), [.leftHalf, .rightHalf])
        XCTAssertEqual(settings.shortcuts(for: .leftHalf).map(\.displayValue), ["Option+Command+Left"])
        XCTAssertEqual(settings.shortcutBindings.map(\.mode), [.leftHalf, .rightHalf])
    }

    func testWindowLayoutShortcutsAreDisabledWithWindowLayoutFeature() {
        let settings = WindowLayoutSettings(
            isEnabled: false,
            modeShortcuts: [
                WindowLayoutModeShortcuts(
                    mode: .leftHalf,
                    shortcuts: [HotKeyBinding(key: "Left", modifiers: ["Option", "Command"])]
                )
            ]
        )

        XCTAssertEqual(settings.shortcutBindings.count, 0)
    }

    func testUpdatingPanelConfigurationPreservesCustomButtonsAndModeOrder() {
        let customButton = WindowLayoutButton(
            id: "custom.focus",
            title: "专注布局",
            modes: [.centered, .maximize]
        )
        let settings = WindowLayoutSettings(customButtons: [customButton])

        let updated = settings.updatingPanelConfiguration(
            isEnabled: false,
            enabledModes: [.rightThird, .leftHalf, .rightHalf],
            modeShortcuts: [
                WindowLayoutModeShortcuts(
                    mode: .rightHalf,
                    shortcuts: [HotKeyBinding(key: "Right", modifiers: ["Option", "Command"])]
                )
            ]
        )

        XCTAssertFalse(updated.isEnabled)
        XCTAssertEqual(updated.enabledModes, [.leftHalf, .rightHalf, .rightThird])
        XCTAssertEqual(updated.customButtons, [customButton])
        XCTAssertEqual(updated.shortcuts(for: .rightHalf).map(\.displayValue), ["Option+Command+Right"])
    }

    func testReplacingPrimaryShortcutOverwritesAndClearsModeBinding() {
        let settings = WindowLayoutSettings(
            modeShortcuts: [
                WindowLayoutModeShortcuts(
                    mode: .leftThird,
                    shortcuts: [HotKeyBinding(key: "Left", modifiers: ["Control", "Option"])]
                )
            ]
        )

        let overwritten = settings.replacingPrimaryShortcut(
            for: .leftThird,
            with: HotKeyBinding(key: "L", modifiers: ["Control", "Command"])
        )
        let cleared = overwritten.replacingPrimaryShortcut(for: .leftThird, with: nil)

        XCTAssertEqual(overwritten.shortcuts(for: .leftThird).map(\.displayValue), ["Control+Command+L"])
        XCTAssertTrue(cleared.shortcuts(for: .leftThird).isEmpty)
        XCTAssertTrue(cleared.modeShortcuts.isEmpty)
    }

    func testWindowLayoutSettingsEditorGroupsModesByMeaning() {
        XCTAssertEqual(
            WindowLayoutSettingsLayout.modeGroups.map(\.title),
            ["半屏", "三分之一", "三分之二", "焦点"]
        )
        XCTAssertEqual(WindowLayoutSettingsLayout.modeGroups.map(\.modes), [
            [.leftHalf, .rightHalf],
            [.leftThird, .rightThird],
            [.leftTwoThirds, .rightTwoThirds],
            [.centered, .maximize]
        ])
    }

    func testModePreviewSegmentsMatchTargetRegions() {
        XCTAssertEqual(WindowLayoutMode.leftHalf.previewSegment, .init(x: 0, y: 0, width: 0.5, height: 1))
        XCTAssertEqual(WindowLayoutMode.rightHalf.previewSegment, .init(x: 0.5, y: 0, width: 0.5, height: 1))
        XCTAssertEqual(WindowLayoutMode.leftThird.previewSegment, .init(x: 0, y: 0, width: 1.0 / 3.0, height: 1))
        XCTAssertEqual(WindowLayoutMode.rightThird.previewSegment, .init(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1))
        XCTAssertEqual(WindowLayoutMode.leftTwoThirds.previewSegment, .init(x: 0, y: 0, width: 2.0 / 3.0, height: 1))
        XCTAssertEqual(WindowLayoutMode.rightTwoThirds.previewSegment, .init(x: 1.0 / 3.0, y: 0, width: 2.0 / 3.0, height: 1))
        XCTAssertEqual(WindowLayoutMode.centered.previewSegment, .init(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        XCTAssertEqual(WindowLayoutMode.maximize.previewSegment, .init(x: 0, y: 0, width: 1, height: 1))
    }
}
