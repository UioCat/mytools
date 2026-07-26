// `SystemWindowLayoutService` 的应用运行时与 AppKit 集成实现。
// 负责生命周期、面板和 macOS 能力接线，不承载可复用的持久化规则。

import AppKit
import ApplicationServices
import CoreGraphics
import MacToolsCore

/// 调用未公开为 Swift API 的辅助功能符号，将窗口元素映射为 Core Graphics 窗口 ID。
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(
    _ element: AXUIElement,
    _ windowID: UnsafeMutablePointer<CGWindowID>
) -> AXError

/// 描述 `SystemWindowLayoutError` 在应用运行时与 AppKit 集成中可取的状态、选项或错误。
enum SystemWindowLayoutError: Error {
    case missingFrontmostApplication
    case missingFocusedWindow
    case missingWindowFrame
    case missingScreen
    case emptyLayoutButton
}

/// 管理 `SystemWindowLayoutService` 在应用运行时与 AppKit 集成中的生命周期、依赖和可变状态。
final class SystemWindowLayoutService {
    /// 封装 `AppliedLayout` 在应用运行时与 AppKit 集成中的值语义和相关操作。
    private struct AppliedLayout {
        var buttonID: String
        var mode: WindowLayoutMode
    }

    private let logger: Logger
    private var appliedLayoutsByWindowID: [CGWindowID: AppliedLayout] = [:]

    /// 创建 `SystemWindowLayoutService`，保存传入依赖并建立初始状态。
    init(logger: Logger) {
        self.logger = logger
    }

    /// 解析前台窗口与所在屏幕，按按钮循环规则计算并写入下一个布局。
    func apply(button: WindowLayoutButton) throws {
        let windowElement = try focusedWindowElement()
        let windowID = windowID(for: windowElement) ?? 0
        let previousMode = appliedLayoutsByWindowID[windowID]?.buttonID == button.id
            ? appliedLayoutsByWindowID[windowID]?.mode
            : nil
        guard let mode = button.mode(after: previousMode) else {
            throw SystemWindowLayoutError.emptyLayoutButton
        }

        let currentAXFrame = try frame(of: windowElement)
        let currentScreenFrame = currentAXFrame.flippedAcrossPrimaryScreen
        let screen = try screen(containing: currentScreenFrame)
        let targetFrame = WindowLayoutCalculator.targetFrame(for: mode, in: screen.visibleFrame)
        let targetAXFrame = targetFrame.flippedAcrossPrimaryScreen

        setFrame(targetAXFrame, for: windowElement)
        appliedLayoutsByWindowID[windowID] = AppliedLayout(buttonID: button.id, mode: mode)
        logger.info("applied window layout \(mode.rawValue) via button \(button.id)")
    }

    /// 更新 `focusedWindowElement` 对应的交互状态，并保持当前选择或展示约束。
    private func focusedWindowElement() throws -> AXUIElement {
        guard
            let application = NSWorkspace.shared.frontmostApplication,
            application.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            throw SystemWindowLayoutError.missingFrontmostApplication
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        guard
            let value = appElement.copyAttribute(kAXFocusedWindowAttribute),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            throw SystemWindowLayoutError.missingFocusedWindow
        }

        return (value as! AXUIElement)
    }

    /// 计算并返回 `frame` 所描述的应用运行时与 AppKit 集成结果。
    private func frame(of windowElement: AXUIElement) throws -> CGRect {
        guard
            let position: CGPoint = windowElement.copyWrappedAttribute(kAXPositionAttribute),
            let size: CGSize = windowElement.copyWrappedAttribute(kAXSizeAttribute)
        else {
            throw SystemWindowLayoutError.missingWindowFrame
        }

        return CGRect(origin: position, size: size)
    }

    /// 按“尺寸、位置、尺寸”顺序写入辅助功能属性，以适配会约束移动后尺寸的窗口。
    private func setFrame(_ frame: CGRect, for windowElement: AXUIElement) {
        // 当前写入接口忽略 AXError；调用方只能确认命令已发出，不能证明目标窗口接受了尺寸。
        windowElement.setSizeAttribute(kAXSizeAttribute, frame.size)
        windowElement.setPointAttribute(kAXPositionAttribute, frame.origin)
        windowElement.setSizeAttribute(kAXSizeAttribute, frame.size)
    }

    /// 计算并返回 `screen` 对应的应用运行时与 AppKit 集成数据或状态结果。
    private func screen(containing rect: CGRect) throws -> NSScreen {
        guard let screen = NSScreen.screens.max(by: { lhs, rhs in
            lhs.frame.intersection(rect).area < rhs.frame.intersection(rect).area
        }) else {
            throw SystemWindowLayoutError.missingScreen
        }

        return screen
    }

    /// 通过私有辅助功能符号取得窗口 ID；失败时回退为无稳定 ID 的布局记录。
    private func windowID(for windowElement: AXUIElement) -> CGWindowID? {
        var windowID = CGWindowID(0)
        let result = _AXUIElementGetWindow(windowElement, &windowID)
        return result == .success ? windowID : nil
    }
}

/// 扩展 `AXUIElement`，补充本文件所需的应用运行时与 AppKit 集成能力。
private extension AXUIElement {
    /// 读取并返回 `copyAttribute` 对应的应用运行时与 AppKit 集成数据。
    func copyAttribute(_ attribute: String) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success else {
            return nil
        }
        return value
    }

    /// 读取并返回 `copyWrappedAttribute` 对应的应用运行时与 AppKit 集成数据。
    func copyWrappedAttribute<T>(_ attribute: String) -> T? {
        guard
            let value = copyAttribute(attribute),
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }

        let success = AXValueGetValue(value as! AXValue, AXValueGetType(value as! AXValue), pointer)
        return success ? pointer.pointee : nil
    }

    /// 应用 `setPointAttribute` 接收的新值，并更新相关应用运行时与 AppKit 集成状态。
    func setPointAttribute(_ attribute: String, _ value: CGPoint) {
        var value = value
        guard let axValue = AXValueCreate(.cgPoint, &value) else {
            return
        }
        AXUIElementSetAttributeValue(self, attribute as CFString, axValue)
    }

    /// 应用 `setSizeAttribute` 接收的新值，并更新相关应用运行时与 AppKit 集成状态。
    func setSizeAttribute(_ attribute: String, _ value: CGSize) {
        var value = value
        guard let axValue = AXValueCreate(.cgSize, &value) else {
            return
        }
        AXUIElementSetAttributeValue(self, attribute as CFString, axValue)
    }
}

/// 扩展 `CGRect`，补充本文件所需的应用运行时与 AppKit 集成能力。
private extension CGRect {
    var flippedAcrossPrimaryScreen: CGRect {
        guard let primaryMaxY = NSScreen.screens.first?.frame.maxY, !isNull else {
            return self
        }

        return CGRect(
            x: origin.x,
            y: primaryMaxY - maxY,
            width: width,
            height: height
        )
    }

    var area: CGFloat {
        guard !isNull else {
            return 0
        }
        return width * height
    }
}
