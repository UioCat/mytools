import AppKit
import XCTest
@testable import MacTools

final class ApplicationMenuTests: XCTestCase {
    @MainActor
    func testEditingShortcutsUseStandardResponderActions() throws {
        _ = NSApplication.shared
        let menu = ApplicationMenu.makeMainMenu()
        let editMenu = try XCTUnwrap(menu.items.first { $0.title == "编辑" }?.submenu)
        let commands: [(String, String, NSEvent.ModifierFlags)] = [
            ("a", "selectAll:", .command),
            ("c", "copy:", .command),
            ("x", "cut:", .command),
            ("v", "paste:", .command),
            ("z", "undo:", .command),
            ("Z", "redo:", [.command, .shift]),
        ]
        for (key, action, modifiers) in commands {
            let item = try XCTUnwrap(editMenu.items.first { $0.action == NSSelectorFromString(action) })
            XCTAssertNil(item.target, "编辑动作必须跟随当前第一响应者")
            XCTAssertEqual(item.keyEquivalent, key)
            XCTAssertEqual(item.keyEquivalentModifierMask, modifiers)
        }
    }

    @MainActor
    func testSelectAllKeyEquivalentSelectsActualText() throws {
        _ = NSApplication.shared
        let menu = ApplicationMenu.makeMainMenu()
        let editMenu = try XCTUnwrap(menu.items.first { $0.title == "编辑" }?.submenu)
        let textView = NSTextView()
        textView.string = "shortcut regression"
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        let item = try XCTUnwrap(editMenu.items.first { $0.action == #selector(NSText.selectAll(_:)) })
        // 测试不依赖桌面焦点；把标准命令交给真实文本编辑器。
        item.target = textView
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
        ))
        XCTAssertTrue(editMenu.performKeyEquivalent(with: event))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: textView.string.utf16.count))
    }

    @MainActor
    func testEditingKeyEquivalentsDispatchOnceAndIgnoreOtherModifiers() throws {
        _ = NSApplication.shared
        let menu = ApplicationMenu.makeMainMenu()
        let editMenu = try XCTUnwrap(menu.items.first { $0.title == "编辑" }?.submenu)
        let responder = EditingActionRecorder()
        for item in editMenu.items where !item.isSeparatorItem {
            item.target = responder
        }
        let commands: [(String, UInt16, NSEvent.ModifierFlags, String)] = [
            ("c", 8, .command, "copy"),
            ("x", 7, .command, "cut"),
            ("v", 9, .command, "paste"),
            ("z", 6, .command, "undo"),
            ("Z", 6, [.command, .shift], "redo"),
        ]
        for (key, code, modifiers, action) in commands {
            responder.actions = []
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: 0, context: nil,
                characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code
            ))
            XCTAssertTrue(editMenu.performKeyEquivalent(with: event))
            XCTAssertEqual(responder.actions, [action])
        }
        for modifiers: NSEvent.ModifierFlags in [[], .option, .control, [.command, .option]] {
            responder.actions = []
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: 0, context: nil,
                characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8
            ))
            XCTAssertFalse(editMenu.performKeyEquivalent(with: event))
            XCTAssertTrue(responder.actions.isEmpty)
        }
    }
}

@MainActor
private final class EditingActionRecorder: NSResponder {
    var actions: [String] = []

    @objc func copy(_ sender: Any?) { actions.append("copy") }
    @objc func cut(_ sender: Any?) { actions.append("cut") }
    @objc func paste(_ sender: Any?) { actions.append("paste") }
    @objc func undo(_ sender: Any?) { actions.append("undo") }
    @objc func redo(_ sender: Any?) { actions.append("redo") }
}
