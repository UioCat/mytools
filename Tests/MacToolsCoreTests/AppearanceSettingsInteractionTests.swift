import AppKit
import SwiftUI
import XCTest
@testable import MacToolsCore

final class AppearanceSettingsInteractionTests: XCTestCase {
    @MainActor
    func testReturningToEditorUsesAppearanceChangedWhileHidden() async {
        let model = AppearanceTestModel()
        let host = NSHostingView(rootView: AppearanceTestHost(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 100)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        await settle(host)

        model.isVisible = false
        await settle(host)
        model.currentMode = .dark
        await settle(host)
        XCTAssertEqual(model.selectedMode, .light)
        model.isVisible = true
        await settle(host)

        XCTAssertEqual(model.selectedMode, .dark)
        XCTAssertEqual(model.saveCount, 0, "Refreshing a draft must not save or overwrite remote settings")
    }

    @MainActor
    private func settle<V: View>(_ host: NSHostingView<V>) async {
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        host.layoutSubtreeIfNeeded()
    }
}

@MainActor
private final class AppearanceTestModel: ObservableObject {
    @Published var isVisible = true
    @Published var currentMode = AppAppearanceMode.light
    @Published var selectedMode = AppAppearanceMode.light
    @Published var message: String?
    var saveCount = 0
}

private struct AppearanceTestHost: View {
    @ObservedObject var model: AppearanceTestModel
    var body: some View {
        if model.isVisible {
            AppearanceSettingsEditor(
                currentMode: model.currentMode,
                selectedMode: $model.selectedMode,
                saveMessage: $model.message,
                saveAppearanceMode: { _ in model.saveCount += 1 }
            )
        } else {
            Text("synthetic alternate pane")
        }
    }
}
