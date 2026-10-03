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
    private struct Binding: Equatable {
        let hotKey: HotKey
        let target: HotKeyTarget
    }

    private let registrar: HotKeyRegistrar
    private var registeredBindings: [Binding] = []
    // 已接受配置允许保留的不可用绑定；回滚丢失的有效绑定不属于此集合。
    private var acceptedBindings: [Binding]?
    private var acceptedUnavailableBindings: [Binding] = []
    private var configuredHandler: (HotKeyTarget) -> Void = { _ in }

    /// 创建 `HotKeyService`，保存传入依赖并建立初始状态。
    public init(registrar: HotKeyRegistrar) {
        self.registrar = registrar
    }

    /// 首次配置保留可用绑定；随后隔离未变化的不可用绑定，新失败恢复原注册。
    @discardableResult
    public func configure(
        settings: AppSettings,
        handler: @escaping (HotKeyTarget) -> Void = { _ in }
    ) -> [HotKeyConfigurationFailure] {
        let requested = uniqueHotKeys(from: settings)
        let previouslyUnavailable = Set(requested.filter {
            acceptedUnavailableBindings.contains($0)
        }.map(\.hotKey))
        let invalid = requested.compactMap { binding -> HotKeyConfigurationFailure? in
            let hotKey = binding.hotKey
            guard HotKeyKeyCatalog.keyCode(for: hotKey.key) != nil else {
                return .init(hotKey: hotKey, underlyingError: HotKeyRegistrationError.unsupportedKey(hotKey.key))
            }
            guard hotKey.modifiers.allSatisfy({ ["Control", "Option", "Shift", "Command"].contains($0) }) else {
                return .init(hotKey: hotKey, underlyingError: HotKeyRegistrationError.unsupportedModifiers(hotKey.modifiers))
            }
            return nil
        }
        let newInvalid = invalid.filter { !previouslyUnavailable.contains($0.hotKey) }
        guard newInvalid.isEmpty || acceptedBindings == nil else { return newInvalid }
        if let acceptedBindings, requested == acceptedBindings,
           registeredBindings == requested.filter({ !acceptedUnavailableBindings.contains($0) }) {
            configuredHandler = handler
            return []
        }

        let previous = registeredBindings
        registrar.unregisterAll()
        let invalidValues = Set(invalid.map { $0.hotKey.displayValue })
        let (accepted, registrationFailures) = register(requested.filter {
            !invalidValues.contains($0.hotKey.displayValue)
        })
        let failures = invalid + registrationFailures
        let newFailures = failures.filter { !previouslyUnavailable.contains($0.hotKey) }
        guard acceptedBindings != nil, !newFailures.isEmpty else {
            let isInitialConfiguration = acceptedBindings == nil
            registeredBindings = accepted
            acceptedBindings = requested
            acceptedUnavailableBindings = requested.filter { !accepted.contains($0) }
            configuredHandler = handler
            return isInitialConfiguration ? failures : []
        }
        registrar.unregisterAll()
        let (restored, restorationFailures) = register(previous)
        registeredBindings = restored
        return newFailures + restorationFailures
    }

    /// 验证保存前注册，并返回恢复本次操作之前有效绑定与处理器的撤销动作。
    public func configureForSave(
        settings: AppSettings,
        handler: @escaping (HotKeyTarget) -> Void = { _ in }
    ) throws -> () -> [HotKeyConfigurationFailure] {
        let previousRegistered = registeredBindings
        let previousAccepted = acceptedBindings
        let previousUnavailable = acceptedUnavailableBindings
        let previousHandler = configuredHandler
        let restore = { [weak self] () -> [HotKeyConfigurationFailure] in
            guard let self else { return [] }
            self.registrar.unregisterAll()
            let (restored, failures) = self.register(previousRegistered)
            self.registeredBindings = restored
            self.acceptedBindings = previousAccepted
            self.acceptedUnavailableBindings = previousUnavailable
            self.configuredHandler = previousHandler
            return failures
        }
        if let failure = configure(settings: settings, handler: handler).first {
            // 初次配置允许部分成功，但保存校验失败仍须还原调用前状态。
            if previousAccepted == nil { _ = restore() }
            throw failure
        }
        return restore
    }

    private func register(_ entries: [Binding])
        -> ([Binding], [HotKeyConfigurationFailure]) {
        var accepted: [Binding] = []
        var failures: [HotKeyConfigurationFailure] = []
        for binding in entries {
            do {
                try registrar.register(binding.hotKey) { [weak self] in
                    self?.configuredHandler(binding.target)
                }
                accepted.append(binding)
            } catch {
                failures.append(.init(hotKey: binding.hotKey, underlyingError: error))
            }
        }
        return (accepted, failures)
    }

    /// 计算并返回 `hotKeys` 对应的全局快捷键领域数据或状态结果。
    private func hotKeys(from settings: AppSettings) -> [Binding] {
        let toolHotKeys = [
            Binding(hotKey: settings.mainPanelShortcut.hotKey, target: .mainPanel),
            Binding(hotKey: settings.clipboardShortcut.hotKey, target: .clipboard),
            Binding(hotKey: settings.reservedTool2Shortcut.hotKey, target: .translation),
            Binding(hotKey: settings.reservedTool3Shortcut.hotKey, target: .screenCapture)
        ]

        let windowLayoutHotKeys = settings.windowLayout.shortcutBindings.map { shortcutBinding in
            Binding(hotKey: shortcutBinding.binding.hotKey, target: .windowLayout(shortcutBinding.mode))
        }

        return toolHotKeys + windowLayoutHotKeys
    }

    /// 按配置顺序去重快捷键，保留同一显示值第一次出现的目标。
    private func uniqueHotKeys(from settings: AppSettings) -> [Binding] {
        var seen = Set<String>()
        return hotKeys(from: settings).filter { binding in
            let hotKey = binding.hotKey
            return hotKey.key.isEmpty == false
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
