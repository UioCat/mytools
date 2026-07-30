// `PasteActionService` 的自动粘贴领域实现。
// 负责剪贴板写入和粘贴事件发送，不决定面板展示内容。

import AppKit
import CoreGraphics
import Foundation

/// 定义 `WritablePasteboard` 在自动粘贴领域中需要满足的能力边界。
public protocol WritablePasteboard {
    /// 保存 `writeText` 接收的自动粘贴领域数据，并保持既有持久化约束。
    func writeText(_ text: String) throws
    /// 保存 `writeFileURL` 接收的自动粘贴领域数据，并保持既有持久化约束。
    func writeFileURL(_ url: URL) throws
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

/// 已完成文件读取和图片规范化、可直接写入系统剪贴板的内容。
public enum PreparedPasteboardContent: Equatable, Sendable {
    case text(String)
    case fileURL(URL)
    case png(Data)
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
        try write(Self.prepareContent(for: item))
    }

    /// 按文本、图片、文件路径的优先级准备可直接写入系统剪贴板的内容。
    public static func prepareContent(
        for item: ClipboardItem
    ) throws -> PreparedPasteboardContent {
        if let text = item.text {
            return .text(text)
        }

        // 图片统一转为 PNG 后写入，确保截图和缓存格式差异不会泄漏到下游应用。
        if item.kind == .imageData, let path = item.cachedFilePath ?? item.originalPath {
            guard
                let imageData = try? Data(contentsOf: URL(fileURLWithPath: path)),
                let pngData = ImageDataNormalizer.pngData(from: imageData)
            else {
                throw PasteActionError.invalidImageData
            }
            return .png(pngData)
        }

        if let path = item.originalPath ?? item.cachedFilePath {
            return .fileURL(URL(fileURLWithPath: path))
        }

        throw PasteActionError.unsupportedItem
    }

    /// 把已准备好的内容写入系统剪贴板，不再访问源文件或解码图片。
    public func write(_ content: PreparedPasteboardContent) throws {
        switch content {
        case let .text(text):
            try pasteboard.writeText(text)
        case let .fileURL(url):
            try pasteboard.writeFileURL(url)
        case let .png(data):
            try pasteboard.writeImageData(data)
        }
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
    case pasteboardWriteFailed
}

/// 将 AppKit 剪贴板的 Bool 写入结果暴露为可测试边界。
protocol AppKitPasteboardWriting: AnyObject {
    func clearContents()
    func setString(_ text: String) -> Bool
    func writeFileURL(_ url: URL) -> Bool
    func setPNGData(_ data: Data) -> Bool
}

/// 把 `NSPasteboard` 适配为最小写入边界。
private final class AppKitPasteboardWriter: AppKitPasteboardWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    func clearContents() {
        pasteboard.clearContents()
    }

    func setString(_ text: String) -> Bool {
        pasteboard.setString(text, forType: .string)
    }

    func writeFileURL(_ url: URL) -> Bool {
        pasteboard.writeObjects([url as NSURL])
    }

    func setPNGData(_ data: Data) -> Bool {
        pasteboard.setData(data, forType: .png)
    }
}

/// 管理 `SystemWritablePasteboard` 在自动粘贴领域中的生命周期、依赖和可变状态。
public final class SystemWritablePasteboard: WritablePasteboard {
    private let writer: any AppKitPasteboardWriting

    /// 创建 `SystemWritablePasteboard`，保存传入依赖并建立初始状态。
    public init(pasteboard: NSPasteboard = .general) {
        self.writer = AppKitPasteboardWriter(pasteboard: pasteboard)
    }

    init(writer: any AppKitPasteboardWriting) {
        self.writer = writer
    }

    /// 保存 `writeText` 接收的自动粘贴领域数据，并保持既有持久化约束。
    public func writeText(_ text: String) throws {
        writer.clearContents()
        guard writer.setString(text) else {
            throw PasteActionError.pasteboardWriteFailed
        }
    }

    /// 保存 `writeFileURL` 接收的自动粘贴领域数据，并保持既有持久化约束。
    public func writeFileURL(_ url: URL) throws {
        writer.clearContents()
        guard writer.writeFileURL(url) else {
            throw PasteActionError.pasteboardWriteFailed
        }
    }

    /// 保存 `writeImageData` 接收的自动粘贴领域数据，并保持既有持久化约束。
    public func writeImageData(_ data: Data) throws {
        writer.clearContents()
        guard writer.setPNGData(data) else {
            throw PasteActionError.pasteboardWriteFailed
        }
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
