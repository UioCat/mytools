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

public struct HotKeyConfigurationFailure: Error, LocalizedError {
    public let hotKey: HotKey
    public let underlyingError: Error

    public var errorDescription: String? {
        "快捷键 \(hotKey.displayValue) 无法注册，请检查按键是否受支持或被其他应用占用。"
    }
}

/// 管理 `HotKeyService` 在全局快捷键领域中的生命周期、依赖和可变状态。
public final class HotKeyService {
    private let registrar: HotKeyRegistrar
    private var configuredHotKeys: [(HotKey, HotKeyTarget)] = []
    private var configuredHandler: (HotKeyTarget) -> Void = { _ in }

    /// 创建 `HotKeyService`，保存传入依赖并建立初始状态。
    public init(registrar: HotKeyRegistrar) {
        self.registrar = registrar
    }

    /// 清除旧注册并按当前设置重新登记工具和窗口布局快捷键。
    @discardableResult
    public func configure(
        settings: AppSettings,
        handler: @escaping (HotKeyTarget) -> Void = { _ in }
    ) -> [HotKeyConfigurationFailure] {
        let requested = uniqueHotKeys(from: settings)
        let invalid = requested.compactMap { hotKey, _ -> HotKeyConfigurationFailure? in
            guard HotKeyKeyCatalog.keyCode(for: hotKey.key) != nil else {
                return .init(hotKey: hotKey, underlyingError: HotKeyRegistrationError.unsupportedKey(hotKey.key))
            }
            guard hotKey.modifiers.allSatisfy({ ["Control", "Option", "Shift", "Command"].contains($0) }) else {
                return .init(hotKey: hotKey, underlyingError: HotKeyRegistrationError.unsupportedModifiers(hotKey.modifiers))
            }
            return nil
        }
        guard invalid.isEmpty || configuredHotKeys.isEmpty else { return invalid }
        if !configuredHotKeys.isEmpty, requested.count == configuredHotKeys.count,
           zip(requested, configuredHotKeys).allSatisfy({ $0.0.0 == $0.1.0 && $0.0.1 == $0.1.1 }) {
            configuredHandler = handler
            return []
        }

        let previous = configuredHotKeys
        registrar.unregisterAll()
        let invalidValues = Set(invalid.map { $0.hotKey.displayValue })
        let (accepted, registrationFailures) = register(requested.filter {
            !invalidValues.contains($0.0.displayValue)
        })
        let failures = invalid + registrationFailures
        guard !failures.isEmpty, !previous.isEmpty else {
            configuredHotKeys = accepted
            configuredHandler = handler
            return failures
        }
        registrar.unregisterAll()
        let (restored, restorationFailures) = register(previous)
        configuredHotKeys = restored
        return failures + restorationFailures
    }

    private func register(_ entries: [(HotKey, HotKeyTarget)])
        -> ([(HotKey, HotKeyTarget)], [HotKeyConfigurationFailure]) {
        var accepted: [(HotKey, HotKeyTarget)] = []
        var failures: [HotKeyConfigurationFailure] = []
        for (hotKey, target) in entries {
            do {
                try registrar.register(hotKey) { [weak self] in
                    self?.configuredHandler(target)
                }
                accepted.append((hotKey, target))
            } catch {
                failures.append(.init(hotKey: hotKey, underlyingError: error))
            }
        }
        return (accepted, failures)
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
        guard let keyCode = HotKeyKeyCatalog.keyCode(for: hotKey.key) else {
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
