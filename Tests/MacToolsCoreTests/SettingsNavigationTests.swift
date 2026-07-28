import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import MacToolsCore

final class SettingsNavigationTests: XCTestCase {
    @MainActor
    func testToolbarHumanCadenceClickChangesEveryBoundPane() {
        var receivedSelections: [SettingsPane] = []
        let toolbar = SettingsPaneToolbarHarness(initialSelection: .sync) {
            receivedSelections.append($0)
        }
        .frame(width: 600, height: 80)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(rootView: toolbar)
        window.isMovableByWindowBackground = true
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.close()
        }

        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        for index in SettingsPane.allCases.indices {
            sendHumanCadenceClick(
                to: window,
                at: NSPoint(x: toolbarButtonCenterX(at: index), y: 40)
            )

            XCTAssertEqual(receivedSelections, Array(SettingsPane.allCases.prefix(index + 1)))
        }

        receivedSelections.removeAll()
        sendHumanCadenceClick(to: window, at: NSPoint(x: 12, y: 40))
        XCTAssertEqual(receivedSelections, [.general])
    }

    func testPanesUseStableToolbarOrder() {
        XCTAssertEqual(
            SettingsPane.allCases,
            [.general, .clipboard, .translation, .automation, .sync]
        )
        XCTAssertEqual(
            SettingsPane.allCases.map(\.title),
            ["通用", "剪贴板", "翻译", "自动化", "数据同步"]
        )
    }

    func testNavigatorMovesBetweenAdjacentPanes() {
        XCTAssertEqual(
            SettingsPaneNavigator.pane(adjacentTo: .clipboard, direction: .previous),
            .general
        )
        XCTAssertEqual(
            SettingsPaneNavigator.pane(adjacentTo: .clipboard, direction: .next),
            .translation
        )
    }

    func testNavigatorWrapsAtBothToolbarEdges() {
        XCTAssertEqual(
            SettingsPaneNavigator.pane(adjacentTo: .general, direction: .previous),
            .sync
        )
        XCTAssertEqual(
            SettingsPaneNavigator.pane(adjacentTo: .sync, direction: .next),
            .general
        )
    }

    func testToolbarScopesArrowKeysToFocusablePaneButtons() throws {
        let source = try sourceFile("Sources/MacToolsCore/UI/SettingsNavigation.swift")

        XCTAssertTrue(source.contains("@FocusState private var focusTarget"))
        XCTAssertTrue(source.contains(".focusable()"))
        XCTAssertTrue(source.contains(".focused($focusTarget"))
        XCTAssertTrue(source.contains(".onKeyPress(.leftArrow)"))
        XCTAssertTrue(source.contains(".onKeyPress(.rightArrow)"))
        XCTAssertFalse(source.contains("KeyboardEventMonitorView"))
    }

    func testEachPaneOwnsOnlyItsRelatedSections() {
        XCTAssertEqual(SettingsPane.general.sections, [.system, .shortcuts])
        XCTAssertEqual(SettingsPane.clipboard.sections, [.clipboard])
        XCTAssertEqual(SettingsPane.translation.sections, [.translation])
        XCTAssertEqual(
            SettingsPane.automation.sections,
            [.superRightClick, .windowLayout, .permissions]
        )
        XCTAssertEqual(SettingsPane.sync.sections, [.sync])
    }

    func testSettingsSectionsUseFlatGroupedContentInsteadOfCards() throws {
        let source = try sourceFile("Sources/MacToolsCore/UI/SettingsComponents.swift")

        XCTAssertTrue(source.contains(".liquidGlassGroup(spacing: 8)"))
        XCTAssertFalse(source.contains("SettingsContentSurfaceModifier"))
        XCTAssertFalse(source.contains("controlBackgroundColor"))
    }

    func testRuntimeRetainsSelectionForCurrentAppSessionAndDefaultsToGeneral() throws {
        let source = try sourceFile("Sources/MacTools/App/RuntimeViews.swift")

        XCTAssertTrue(
            source.contains("@State private var selectedSettingsPane: SettingsPane = .general")
        )
        XCTAssertTrue(source.contains("selectedPane: $selectedSettingsPane"))
    }

    private func sourceFile(_ path: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    @MainActor
    private func sendHumanCadenceClick(to window: NSWindow, at location: NSPoint) {
        let mouseDown = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )
        let mouseUp = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime + 0.01,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 0
        )

        if let mouseDown {
            window.sendEvent(mouseDown)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        if let mouseUp {
            window.sendEvent(mouseUp)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
    }

    private func toolbarButtonCenterX(at index: Int) -> CGFloat {
        let toolbarWidth: CGFloat = 600
        let toolbarHorizontalPadding: CGFloat = 8
        let buttonSpacing: CGFloat = 8
        let buttonCount = CGFloat(SettingsPane.allCases.count)
        let contentWidth = toolbarWidth - (toolbarHorizontalPadding * 2)
        let buttonWidth = (contentWidth - buttonSpacing * (buttonCount - 1)) / buttonCount

        return toolbarHorizontalPadding
            + CGFloat(index) * (buttonWidth + buttonSpacing)
            + buttonWidth / 2
    }
}

private struct SettingsPaneToolbarHarness: View {
    @State private var selection: SettingsPane
    let onSelectionChange: (SettingsPane) -> Void

    init(
        initialSelection: SettingsPane,
        onSelectionChange: @escaping (SettingsPane) -> Void
    ) {
        self._selection = State(initialValue: initialSelection)
        self.onSelectionChange = onSelectionChange
    }

    var body: some View {
        SettingsPaneToolbar(selection: $selection)
            .onChange(of: selection) { _, pane in
                onSelectionChange(pane)
            }
    }
}
