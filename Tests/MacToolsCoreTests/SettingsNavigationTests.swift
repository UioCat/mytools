import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import MacToolsCore

final class SettingsNavigationTests: XCTestCase {
    @MainActor
    func testToolbarClickChangesTheBoundPane() {
        var selection = SettingsPane.general
        let toolbar = SettingsPaneToolbar(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        )
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
        sendClick(to: window, at: NSPoint(x: 180, y: 40))
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

        XCTAssertEqual(selection, .clipboard)
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

    func testSettingsSectionsUseQuietContentSurfaceInsteadOfLiquidGlass() throws {
        let source = try sourceFile("Sources/MacToolsCore/UI/SettingsComponents.swift")

        XCTAssertTrue(source.contains(".settingsContentSurface(cornerRadius: 20)"))
        XCTAssertFalse(source.contains(".liquidGlassModule(cornerRadius: 22)"))
    }

    func testRuntimeRetainsSelectionForCurrentAppSessionAndDefaultsToGeneral() throws {
        let source = try sourceFile("Sources/MacTools/App/RuntimeViews.swift")

        XCTAssertTrue(
            source.contains("@State private var selectedSettingsPane: SettingsPane = .general")
        )
        XCTAssertTrue(source.contains("selectedPane: $selectedSettingsPane"))
    }

    func testToolbarSelectionDoesNotAnimateIdentifiedContentReplacement() throws {
        let source = try sourceFile("Sources/MacToolsCore/UI/SettingsNavigation.swift")

        XCTAssertTrue(source.contains("return Button {\n            selection = pane"))
        XCTAssertFalse(
            source.contains(
                """
                return Button {
                            withAnimation
                """
            )
        )
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
    private func sendClick(to window: NSWindow, at location: NSPoint) {
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
        }
        if let mouseUp {
            window.sendEvent(mouseUp)
        }
    }
}
