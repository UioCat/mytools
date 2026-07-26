// `HotKeyService` 的全局快捷键领域实现。
// 负责快捷键建模、注册和分发，不管理具体工具界面。

import Foundation

#if canImport(Carbon)
import Carbon
#endif

/// 描述 `HotKeyRegistrationError` 在全局快捷键领域中可取的状态、选项或错误。
public enum HotKeyRegistrationError: Error, Equatable {
    case unsupportedKey(String)
    case unsupportedModifiers([String])
    case registrationFailed(OSStatus)
}

/// 管理 `HotKeyService` 在全局快捷键领域中的生命周期、依赖和可变状态。
public final class HotKeyService {
    private let registrar: HotKeyRegistrar
    private var bindings: [String: HotKeyTarget] = [:]

    /// 创建 `HotKeyService`，保存传入依赖并建立初始状态。
    public init(registrar: HotKeyRegistrar) {
        self.registrar = registrar
    }

    /// 清除旧注册并按当前设置重新登记工具和窗口布局快捷键。
    public func configure(
        settings: AppSettings,
        handler: @escaping (HotKeyTarget) -> Void = { _ in }
    ) {
        registrar.unregisterAll()
        bindings.removeAll()

        // 当前实现先记录显示值映射，再尝试系统注册；注册错误由调用路径忽略。
        for (hotKey, target) in uniqueHotKeys(from: settings) {
            bindings[hotKey.displayValue] = target
            try? registrar.register(hotKey) {
                handler(target)
            }
        }
    }

    /// 返回当前配置记录的显示值映射，不代表 Carbon 注册一定成功。
    public func binding(for displayValue: String) -> HotKeyTarget? {
        bindings[displayValue]
    }

    /// 计算并返回 `hotKeys` 对应的全局快捷键领域数据或状态结果。
    private func hotKeys(from settings: AppSettings) -> [(HotKey, HotKeyTarget)] {
        let toolHotKeys: [(HotKey, HotKeyTarget)] = [
            (settings.mainPanelShortcut.hotKey, .mainPanel),
            (settings.clipboardShortcut.hotKey, .clipboard),
            (settings.reservedTool2Shortcut.hotKey, .translation),
            (settings.reservedTool3Shortcut.hotKey, .screenCapture)
        ]

        let windowLayoutHotKeys = settings.windowLayout.shortcutBindings.map { shortcutBinding in
            (shortcutBinding.binding.hotKey, HotKeyTarget.windowLayout(shortcutBinding.mode))
        }

        return toolHotKeys + windowLayoutHotKeys
    }

    /// 按配置顺序去重快捷键，保留同一显示值第一次出现的目标。
    private func uniqueHotKeys(from settings: AppSettings) -> [(HotKey, HotKeyTarget)] {
        var seen = Set<String>()
        return hotKeys(from: settings).filter { hotKey, _ in
            hotKey.key.isEmpty == false
                && hotKey.modifiers.isEmpty == false
                && seen.insert(hotKey.displayValue).inserted
        }
    }
}

/// 扩展 `HotKeyBinding`，补充本文件所需的全局快捷键领域能力。
private extension HotKeyBinding {
    var hotKey: HotKey {
        HotKey(displayValue: displayValue, key: key, modifiers: modifiers)
    }
}

#if canImport(Carbon)
/// 管理 `CarbonHotKeyRegistrar` 在全局快捷键领域中的生命周期、依赖和可变状态。
public final class CarbonHotKeyRegistrar: HotKeyRegistrar {
    private let keyCodes: [String: UInt32] = [
        "A": 0,
        "S": 1,
        "D": 2,
        "F": 3,
        "H": 4,
        "G": 5,
        "Z": 6,
        "X": 7,
        "C": 8,
        "V": 9,
        "B": 11,
        "Q": 12,
        "W": 13,
        "E": 14,
        "R": 15,
        "Y": 16,
        "T": 17,
        "1": 18,
        "2": 19,
        "3": 20,
        "4": 21,
        "6": 22,
        "5": 23,
        "7": 26,
        "8": 28,
        "9": 25,
        "0": 29,
        "O": 31,
        "U": 32,
        "I": 34,
        "P": 35,
        "Return": 36,
        "L": 37,
        "J": 38,
        "K": 40,
        "N": 45,
        "M": 46,
        "Tab": 48,
        "Space": 49,
        "Delete": 51,
        "Escape": 53,
        "F5": 96,
        "F6": 97,
        "F7": 98,
        "F3": 99,
        "F8": 100,
        "F9": 101,
        "F11": 103,
        "F10": 109,
        "F12": 111,
        "F4": 118,
        "F2": 120,
        "F1": 122,
        "Left": 123,
        "Right": 124,
        "Down": 125,
        "Up": 126
    ]
    private let modifierValues: [String: UInt32] = [
        "Control": UInt32(controlKey),
        "Option": UInt32(optionKey),
        "Shift": UInt32(shiftKey),
        "Command": UInt32(cmdKey)
    ]
    private let signature = OSType.from(string: "MTHK")

    private var eventHandler: EventHandlerRef?
    private var handlers: [UInt32: () -> Void] = [:]
    private var registrations: [UInt32: EventHotKeyRef] = [:]
    private var nextIdentifier: UInt32 = 1

    /// 创建 `CarbonHotKeyRegistrar`，保存传入依赖并建立初始状态。
    public init() {
        installEventHandler()
    }

    /// 释放当前实例持有的观察者、任务或系统资源。
    deinit {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    /// 启动 `register` 对应的全局快捷键领域流程，并建立所需资源。
    public func register(_ hotKey: HotKey, handler: @escaping () -> Void) throws {
        guard let keyCode = keyCodes[hotKey.key] else {
            throw HotKeyRegistrationError.unsupportedKey(hotKey.key)
        }
        let modifiers = try carbonModifiers(for: hotKey.modifiers)

        let identifier = nextIdentifier
        nextIdentifier += 1

        let hotKeyID = EventHotKeyID(signature: signature, id: identifier)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            throw HotKeyRegistrationError.registrationFailed(status)
        }

        registrations[identifier] = hotKeyRef
        handlers[identifier] = handler
    }

    /// 结束 `unregisterAll` 对应的全局快捷键领域流程，并释放或重置相关资源。
    public func unregisterAll() {
        for hotKeyRef in registrations.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        registrations.removeAll()
        handlers.removeAll()
    }

    /// 计算并返回 `carbonModifiers` 对应的全局快捷键领域数据或状态结果。
    private func carbonModifiers(for modifiers: [String]) throws -> UInt32 {
        guard !modifiers.isEmpty else {
            throw HotKeyRegistrationError.unsupportedModifiers(modifiers)
        }

        var carbonModifiers: UInt32 = 0
        for modifier in modifiers {
            guard let modifierValue = modifierValues[modifier] else {
                throw HotKeyRegistrationError.unsupportedModifiers(modifiers)
            }
            carbonModifiers |= modifierValue
        }
        return carbonModifiers
    }

    /// 启动 `installEventHandler` 对应的全局快捷键领域流程，并建立所需资源。
    private func installEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else {
                    return status
                }

                let registrar = Unmanaged<CarbonHotKeyRegistrar>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                registrar.invokeHandler(for: hotKeyID.id)
                return noErr
            },
            1,
            &eventSpec,
            userData,
            &eventHandler
        )
    }

    /// 计算并返回 `invokeHandler` 对应的全局快捷键领域数据或状态结果。
    private func invokeHandler(for identifier: UInt32) {
        handlers[identifier]?()
    }
}

/// 扩展 `OSType`，补充本文件所需的全局快捷键领域能力。
private extension OSType {
    /// 计算并返回 `from` 对应的全局快捷键领域数据或状态结果。
    static func from(string: String) -> OSType {
        string.utf8.reduce(0) { value, character in
            (value << 8) + OSType(character)
        }
    }
}
#else
/// 管理 `CarbonHotKeyRegistrar` 在全局快捷键领域中的生命周期、依赖和可变状态。
public final class CarbonHotKeyRegistrar: HotKeyRegistrar {
    /// 创建 `CarbonHotKeyRegistrar`，保存传入依赖并建立初始状态。
    public init() {}

    /// 启动 `register` 对应的全局快捷键领域流程，并建立所需资源。
    public func register(_ hotKey: HotKey, handler: @escaping () -> Void) throws {}

    /// 结束 `unregisterAll` 对应的全局快捷键领域流程，并释放或重置相关资源。
    public func unregisterAll() {}
}
#endif
