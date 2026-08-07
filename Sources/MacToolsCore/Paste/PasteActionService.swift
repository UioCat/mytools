// `PasteActionService` 的自动粘贴领域实现。
// 负责剪贴板写入和粘贴事件发送，不决定面板展示内容。

import AppKit
import CoreGraphics
import Foundation

public extension Notification.Name {
    /// MacTools 自己完成系统剪贴板写入后发送，供采样器立即读取而无需等待周期定时器。
    static let macToolsPasteboardDidWrite = Notification.Name(
        "com.mactools.pasteboard.did-write"
    )
}

/// 定义 `WritablePasteboard` 在自动粘贴领域中需要满足的能力边界。
public protocol WritablePasteboard {
    /// 保存 `writeText` 接收的自动粘贴领域数据，并保持既有持久化约束。
    func writeText(_ text: String)
    /// 保存 `writeFileURL` 接收的自动粘贴领域数据，并保持既有持久化约束。
    func writeFileURL(_ url: URL)
    /// 保存 `writeImageData` 接收的自动粘贴领域数据，并保持既有持久化约束。
    func writeImageData(_ data: Data) throws
}

/// 定义 `PasteEventSender` 在自动粘贴领域中需要满足的能力边界。
public protocol PasteEventSender {
    /// 执行 `sendCopyShortcut` 对应的自动粘贴领域输入输出操作。
    func sendCopyShortcut()
    /// 执行 `sendPasteShortcut` 对应的自动粘贴领域输入输出操作。
    func sendPasteShortcut()
}

/// 管理 `PasteActionService` 在自动粘贴领域中的生命周期、依赖和可变状态。
public final class PasteActionService {
    private let pasteboard: WritablePasteboard
    private let eventSender: PasteEventSender

    /// 创建 `PasteActionService`，保存传入依赖并建立初始状态。
    public init(pasteboard: WritablePasteboard, eventSender: PasteEventSender) {
        self.pasteboard = pasteboard
        self.eventSender = eventSender
    }

    /// 按文本、图片、文件路径的优先级把剪贴板条目写回系统剪贴板。
    public func copy(_ item: ClipboardItem) throws {
        if let text = item.text {
            pasteboard.writeText(text)
            return
        }

        // 图片统一转为 PNG 后写入，确保截图和缓存格式差异不会泄漏到下游应用。
        if item.kind == .imageData, let path = item.cachedFilePath ?? item.originalPath {
            let imageData = try Data(contentsOf: URL(fileURLWithPath: path))
            try pasteboard.writeImageData(imageData)
            return
        }

        if let path = item.originalPath ?? item.cachedFilePath {
            pasteboard.writeFileURL(URL(fileURLWithPath: path))
            return
        }

        throw PasteActionError.unsupportedItem
    }

    /// 先更新系统剪贴板，再发送 Command+V；写入失败时不会发送粘贴事件。
    public func copyAndPaste(_ item: ClipboardItem) throws {
        try copy(item)
        paste()
    }

    /// 执行 `paste` 对应的自动粘贴领域输入输出操作。
    public func paste() {
        eventSender.sendPasteShortcut()
    }
}

/// 描述 `PasteActionError` 在自动粘贴领域中可取的状态、选项或错误。
public enum PasteActionError: Error, Equatable {
    case unsupportedItem
    case invalidImageData
}

/// 管理 `SystemWritablePasteboard` 在自动粘贴领域中的生命周期、依赖和可变状态。
public final class SystemWritablePasteboard: WritablePasteboard {
    private let pasteboard: NSPasteboard
    private let notificationCenter: NotificationCenter

    /// 创建 `SystemWritablePasteboard`，保存传入依赖并建立初始状态。
    public init(
        pasteboard: NSPasteboard = .general,
        notificationCenter: NotificationCenter = .default
    ) {
        self.pasteboard = pasteboard
        self.notificationCenter = notificationCenter
    }

    /// 保存 `writeText` 接收的自动粘贴领域数据，并保持既有持久化约束。
    public func writeText(_ text: String) {
        pasteboard.clearContents()
        if pasteboard.setString(text, forType: .string) {
            notifySuccessfulWrite()
        }
    }

    /// 保存 `writeFileURL` 接收的自动粘贴领域数据，并保持既有持久化约束。
    public func writeFileURL(_ url: URL) {
        pasteboard.clearContents()
        if pasteboard.writeObjects([url as NSURL]) {
            notifySuccessfulWrite()
        }
    }

    /// 保存 `writeImageData` 接收的自动粘贴领域数据，并保持既有持久化约束。
    public func writeImageData(_ data: Data) throws {
        guard let pngData = ImageDataNormalizer.pngData(from: data) else {
            throw PasteActionError.invalidImageData
        }

        pasteboard.clearContents()
        if pasteboard.setData(pngData, forType: .png) {
            notifySuccessfulWrite()
        }
    }

    private func notifySuccessfulWrite() {
        notificationCenter.post(
            name: .macToolsPasteboardDidWrite,
            object: pasteboard
        )
    }
}

/// 管理 `SystemPasteEventSender` 在自动粘贴领域中的生命周期、依赖和可变状态。
public final class SystemPasteEventSender: PasteEventSender {
    /// 创建 `SystemPasteEventSender`，保存传入依赖并建立初始状态。
    public init() {}

    /// 执行 `sendCopyShortcut` 对应的自动粘贴领域输入输出操作。
    public func sendCopyShortcut() {
        sendCommandShortcut(virtualKey: 8)
    }

    /// 执行 `sendPasteShortcut` 对应的自动粘贴领域输入输出操作。
    public func sendPasteShortcut() {
        sendCommandShortcut(virtualKey: 9)
    }

    /// 通过 HID event tap 成对发送 Command 快捷键的按下和抬起事件。
    private func sendCommandShortcut(virtualKey: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)

        keyDown?.flags = [.maskCommand]
        keyUp?.flags = [.maskCommand]
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
