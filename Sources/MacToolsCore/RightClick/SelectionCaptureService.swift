// `SelectionCaptureService` 的超级右键领域实现。
// 负责事件决策、选区解析和动作路由，不安装系统级事件监听。

import Foundation

#if canImport(ApplicationServices)
import ApplicationServices
#endif

#if canImport(AppKit)
import AppKit
#endif

/// 定义 `SelectionCapturing` 在超级右键领域中需要满足的能力边界。
public protocol SelectionCapturing {
    /// 优先通过 Accessibility 读取选中文本，失败时发送复制快捷键并读取剪贴板载荷。
    func captureSelection() -> ClipboardPayload
}

/// 定义 `SelectedTextReading` 在超级右键领域中需要满足的能力边界。
public protocol SelectedTextReading {
    /// 读取并返回 `readSelectedText` 对应的超级右键领域数据。
    func readSelectedText() -> String?
}

/// 管理 `SelectionCaptureService` 在超级右键领域中的生命周期、依赖和可变状态。
public final class SelectionCaptureService: SelectionCapturing {
    private let pasteboard: PasteboardClient
    private let eventSender: PasteEventSender
    private let selectedTextReader: SelectedTextReading
    private let logger: Logger?

    /// 创建 `SelectionCaptureService`，保存传入依赖并建立初始状态。
    public init(
        pasteboard: PasteboardClient,
        eventSender: PasteEventSender,
        selectedTextReader: SelectedTextReading = SystemSelectedTextReader(),
        logger: Logger? = nil
    ) {
        self.pasteboard = pasteboard
        self.eventSender = eventSender
        self.selectedTextReader = selectedTextReader
        self.logger = logger
    }

    /// 捕获 `captureSelection` 对应的超级右键领域上下文，并返回可继续处理的结果。
    public func captureSelection() -> ClipboardPayload {
        // Accessibility 不会改写用户剪贴板，因此只要返回可用文本就优先采用。
        let accessibilityValue = selectedTextReader.readSelectedText()
        if let selectedText = Self.normalizedAccessibilityText(accessibilityValue) {
            logger?.info("selection capture read selected text via accessibility")
            return ClipboardPayload(text: selectedText)
        }
        if accessibilityValue != nil {
            logger?.info("selection capture ignored unusable accessibility text")
        }

        // 复制降级路径以 changeCount 判断目标应用是否真的响应，避免返回旧剪贴板内容。
        let changeCountBeforeCopy = pasteboard.changeCount
        logger?.info("selection capture falling back to copy shortcut")
        eventSender.sendCopyShortcut()
        Thread.sleep(forTimeInterval: 0.12)

        guard pasteboard.changeCount != changeCountBeforeCopy else {
            logger?.error("selection capture copy fallback produced no pasteboard change")
            return ClipboardPayload()
        }

        logger?.info("selection capture read payload from pasteboard after copy")
        return pasteboard.readPayload()
    }

    /// 转换 `normalizedAccessibilityText` 接收的超级右键领域数据，并返回规范化结果。
    private static func normalizedAccessibilityText(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty,
              !normalized.unicodeScalars.contains(where: { $0.value == 0xFFFC }) else {
            return nil
        }
        return normalized
    }
}

/// 管理 `SystemSelectedTextReader` 在超级右键领域中的生命周期、依赖和可变状态。
public final class SystemSelectedTextReader: SelectedTextReading {
    /// 创建 `SystemSelectedTextReader`，保存传入依赖并建立初始状态。
    public init() {}

    /// 先查询系统级聚焦元素，再回退到前台应用的 Accessibility 树读取选中文本。
    public func readSelectedText() -> String? {
        #if canImport(ApplicationServices)
        if let text = readSelectedText(from: AXUIElementCreateSystemWide()) {
            return text
        }

        #if canImport(AppKit)
        guard let processIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }

        return readSelectedText(from: AXUIElementCreateApplication(processIdentifier))
        #else
        return nil
        #endif
        #else
        return nil
        #endif
    }

    #if canImport(ApplicationServices)
    /// 读取并返回 `readSelectedText` 对应的超级右键领域数据。
    private func readSelectedText(from element: AXUIElement) -> String? {
        if let focusedElement = copyAXElementAttribute(kAXFocusedUIElementAttribute, from: element),
           let text = copySelectedText(from: focusedElement) {
            return text
        }

        return copySelectedText(from: element)
    }

    /// 执行 `copySelectedText` 对应的超级右键领域输入输出操作。
    private func copySelectedText(from element: AXUIElement) -> String? {
        copyAttribute(kAXSelectedTextAttribute, from: element) as? String
    }

    /// 读取并返回 `copyAttribute` 对应的超级右键领域数据。
    private func copyAttribute(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else {
            return nil
        }

        return value
    }

    /// 执行 `copyAXElementAttribute` 对应的超级右键领域输入输出操作。
    private func copyAXElementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        guard let value = copyAttribute(attribute, from: element) else {
            return nil
        }

        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }
    #endif
}
