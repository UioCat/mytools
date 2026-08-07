// 使用 Accessibility API 调整其他应用窗口的系统适配器。
// 负责读取聚焦窗口和写入位置尺寸，布局矩形计算由 MacToolsCore 提供。

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

private let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface"

/// 描述 `SystemWindowLayoutError` 在应用运行时与 AppKit 集成中可取的状态、选项或错误。
enum SystemWindowLayoutError: Error {
    case missingFrontmostApplication
    case missingFocusedWindow
    case missingWindowFrame
    case missingScreen
    case emptyLayoutButton
}

/// 管理 `SystemWindowLayoutService` 在应用运行时与 AppKit 集成中的生命周期、依赖和可变状态。
@MainActor
final class SystemWindowLayoutService {
    /// 封装 `AppliedLayout` 在应用运行时与 AppKit 集成中的值语义和相关操作。
    private struct AppliedLayout {
        var buttonID: String
        var mode: WindowLayoutMode
        var targetFrame: CGRect
    }

    /// 保存前台应用元素和其当前聚焦窗口。
    private struct FocusedWindowContext {
        var applicationElement: AXUIElement
        var windowElement: AXUIElement
    }

    /// 保存单次窗口矩形应用所需的稳定上下文。
    private struct FrameApplicationRequest {
        var id: UInt
        var applicationElement: AXUIElement
        var windowElement: AXUIElement
        var windowID: CGWindowID?
        var layout: AppliedLayout
        var targetFrame: CGRect
        var isInitialCrossDisplayWrite: Bool
        var shouldRestoreEnhancedUserInterface: Bool
    }

    /// 保存位置和尺寸的独立回读结果及错误码。
    private struct FrameReadback {
        var position: CGPoint?
        var size: CGSize?
        var positionError: AXError
        var sizeError: AXError
    }

    private let logger: Logger
    private var appliedLayoutsByWindowID: [CGWindowID: AppliedLayout] = [:]
    private var activeFrameApplicationRequest: FrameApplicationRequest?
    private var activeFrameApplicationTask: Task<Void, Never>?
    private var nextFrameApplicationRequestID: UInt = 0

    /// 创建 `SystemWindowLayoutService`，保存传入依赖并建立初始状态。
    init(logger: Logger) {
        self.logger = logger
    }

    /// 解析前台窗口与所在屏幕，按按钮循环规则计算并写入下一个布局。
    func apply(button: WindowLayoutButton) throws {
        let context = try focusedWindowContext()
        let windowElement = context.windowElement
        let windowID = windowID(for: windowElement)
        let pendingLayout = activeFrameApplicationRequest.flatMap { request in
            CFEqual(request.windowElement, windowElement) ? request.layout : nil
        }
        let previousLayout = pendingLayout ?? windowID.flatMap { appliedLayoutsByWindowID[$0] }
        let previousMode = previousLayout?.buttonID == button.id
            ? previousLayout?.mode
            : nil
        guard let requestedMode = button.mode(after: previousMode) else {
            throw SystemWindowLayoutError.emptyLayoutButton
        }

        let currentAXFrame = try frame(of: windowElement)
        let currentScreenFrame = currentAXFrame.flippedAcrossPrimaryScreen
        let screen = try screen(containing: currentScreenFrame)
        let currentScreen = layoutScreen(for: screen)
        let successfulLayout = windowID.flatMap { appliedLayoutsByWindowID[$0] }
        let successfulMode = successfulLayout?.buttonID == button.id
            ? successfulLayout?.mode
            : nil
        let successfulTargetFrame = successfulLayout?.buttonID == button.id
            ? successfulLayout?.targetFrame
            : nil
        let target = WindowScreenNavigationPolicy.target(
            requestedMode: requestedMode,
            currentFrame: currentScreenFrame,
            previousMode: successfulMode,
            previousTargetFrame: successfulTargetFrame,
            currentScreen: currentScreen,
            screens: NSScreen.screens.map(layoutScreen(for:)),
            allowsTraversal: button.id == "mode.\(requestedMode.rawValue)"
                && button.modes == [requestedMode]
        )
        let targetAXFrame = target.frame.flippedAcrossPrimaryScreen

        cancelActiveFrameApplication()
        nextFrameApplicationRequestID &+= 1
        let request = FrameApplicationRequest(
            id: nextFrameApplicationRequestID,
            applicationElement: context.applicationElement,
            windowElement: windowElement,
            windowID: windowID,
            layout: AppliedLayout(
                buttonID: button.id,
                mode: target.mode,
                targetFrame: target.frame
            ),
            targetFrame: targetAXFrame,
            isInitialCrossDisplayWrite: target.screen.id != currentScreen.id,
            shouldRestoreEnhancedUserInterface: disableEnhancedUserInterfaceIfNeeded(
                for: context.applicationElement
            )
        )
        activeFrameApplicationRequest = request
        activeFrameApplicationTask = Task { @MainActor [weak self] in
            await self?.applyFrame(request, initialFrame: currentAXFrame)
        }
    }

    /// 读取前台应用元素和当前聚焦窗口，供属性兼容处理与窗口写入共同使用。
    private func focusedWindowContext() throws -> FocusedWindowContext {
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

        return FocusedWindowContext(
            applicationElement: appElement,
            windowElement: value as! AXUIElement
        )
    }

    /// 计算并返回 `frame` 所描述的应用运行时与 AppKit 集成结果。
    private func frame(of windowElement: AXUIElement) throws -> CGRect {
        let readback = frameReadback(of: windowElement)
        guard let position = readback.position, let size = readback.size else {
            throw SystemWindowLayoutError.missingWindowFrame
        }

        return CGRect(origin: position, size: size)
    }

    /// 独立读取位置和尺寸，单项失败时仍保留另一项的有效结果。
    private func frameReadback(of windowElement: AXUIElement) -> FrameReadback {
        let position: (value: CGPoint?, error: AXError) = windowElement.copyWrappedAttribute(
            kAXPositionAttribute,
            type: .cgPoint
        )
        let size: (value: CGSize?, error: AXError) = windowElement.copyWrappedAttribute(
            kAXSizeAttribute,
            type: .cgSize
        )
        return FrameReadback(
            position: position.value,
            size: size.value,
            positionError: position.error,
            sizeError: size.error
        )
    }

    /// 根据实际变化方向写入位置和尺寸，并以独立回读结果驱动有限重试。
    private func applyFrame(
        _ request: FrameApplicationRequest,
        initialFrame: CGRect
    ) async {
        let startedAt = ProcessInfo.processInfo.systemUptime
        var lastKnownFrame = initialFrame
        var mismatches = WindowFrameApplicationPolicy.mismatchedComponents(
            actualPosition: initialFrame.origin,
            actualSize: initialFrame.size,
            target: request.targetFrame
        )
        var blockedComponents: WindowFrameComponents = []
        var writeAttempts = 0
        var lastReadback = FrameReadback(
            position: initialFrame.origin,
            size: initialFrame.size,
            positionError: .success,
            sizeError: .success
        )

        if mismatches.isEmpty {
            completeFrameApplication(request, writeAttempts: writeAttempts)
            return
        }

        while isActive(request) {
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            guard elapsed < WindowFrameApplicationPolicy.verificationTimeout else {
                failFrameApplication(
                    request,
                    writeAttempts: writeAttempts,
                    mismatches: mismatches,
                    readback: lastReadback
                )
                return
            }

            let writableComponents = mismatches.subtracting(blockedComponents)
            if
                !writableComponents.isEmpty,
                WindowFrameApplicationPolicy.shouldWrite(
                    afterAttempt: writeAttempts,
                    elapsed: elapsed
                )
            {
                writeAttempts += 1
                let mutations = WindowFrameApplicationPolicy.mutationPlan(
                    current: lastKnownFrame,
                    target: request.targetFrame,
                    components: writableComponents,
                    isInitialCrossDisplayWrite: request.isInitialCrossDisplayWrite
                        && writeAttempts == 1
                )
                apply(
                    mutations,
                    to: request.windowElement,
                    requestID: request.id,
                    attempt: writeAttempts,
                    blockedComponents: &blockedComponents
                )
            }

            let remaining = WindowFrameApplicationPolicy.verificationTimeout
                - (ProcessInfo.processInfo.systemUptime - startedAt)
            guard remaining > 0 else {
                continue
            }
            let delay = min(
                WindowFrameApplicationPolicy.verificationDelay(afterAttempt: writeAttempts - 1),
                remaining
            )
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard isActive(request) else {
                return
            }

            lastReadback = frameReadback(of: request.windowElement)
            if let position = lastReadback.position {
                lastKnownFrame.origin = position
            }
            if let size = lastReadback.size {
                lastKnownFrame.size = size
            }
            mismatches = WindowFrameApplicationPolicy.mismatchedComponents(
                actualPosition: lastReadback.position,
                actualSize: lastReadback.size,
                target: request.targetFrame
            )
            if mismatches.isEmpty {
                completeFrameApplication(request, writeAttempts: writeAttempts)
                return
            }
        }
    }

    /// 顺序执行本轮计划；确定性错误会阻止同一属性在后续轮次继续写入。
    private func apply(
        _ mutations: [WindowFrameMutation],
        to windowElement: AXUIElement,
        requestID: UInt,
        attempt: Int,
        blockedComponents: inout WindowFrameComponents
    ) {
        for mutation in mutations {
            let component: WindowFrameComponents
            let result: AXError
            switch mutation {
            case .position(let position):
                component = .position
                guard !blockedComponents.contains(component) else {
                    continue
                }
                result = windowElement.setPointAttribute(kAXPositionAttribute, position)
            case .size(let size):
                component = .size
                guard !blockedComponents.contains(component) else {
                    continue
                }
                result = windowElement.setSizeAttribute(kAXSizeAttribute, size)
            }

            guard result != .success else {
                continue
            }
            logger.error(
                "window layout AX write failed request=\(requestID) attempt=\(attempt) "
                    + "component=\(component.logValue) error=\(result.rawValue)"
            )
            if isDeterministicWriteFailure(result) {
                blockedComponents.insert(component)
            }
        }
    }

    /// 新请求到来时停止旧任务，旧任务在下一次代次检查前不得继续写入。
    private func cancelActiveFrameApplication() {
        guard let request = activeFrameApplicationRequest else {
            return
        }
        activeFrameApplicationTask?.cancel()
        restoreEnhancedUserInterfaceIfNeeded(for: request)
        activeFrameApplicationTask = nil
        activeFrameApplicationRequest = nil
        logger.info(
            "cancelled window layout request=\(request.id) mode=\(request.layout.mode.rawValue)"
        )
    }

    /// 回读确认位置和尺寸都已到位后，才更新按窗口保存的布局循环状态。
    private func completeFrameApplication(
        _ request: FrameApplicationRequest,
        writeAttempts: Int
    ) {
        guard isActive(request) else {
            return
        }
        if let windowID = request.windowID {
            appliedLayoutsByWindowID[windowID] = request.layout
        }
        restoreEnhancedUserInterfaceIfNeeded(for: request)
        activeFrameApplicationTask = nil
        activeFrameApplicationRequest = nil
        logger.info(
            "applied window layout \(request.layout.mode.rawValue) "
                + "via button \(request.layout.buttonID) request=\(request.id) "
                + "after \(writeAttempts) write attempt(s)"
        )
    }

    /// 达到总时限仍未匹配时结束请求，不污染已成功布局状态。
    private func failFrameApplication(
        _ request: FrameApplicationRequest,
        writeAttempts: Int,
        mismatches: WindowFrameComponents,
        readback: FrameReadback
    ) {
        guard isActive(request) else {
            return
        }
        restoreEnhancedUserInterfaceIfNeeded(for: request)
        activeFrameApplicationTask = nil
        activeFrameApplicationRequest = nil
        logger.error(
            "window layout verification timed out request=\(request.id) "
                + "mode=\(request.layout.mode.rawValue) attempts=\(writeAttempts) "
                + "components=\(mismatches.logValue) "
                + "positionReadError=\(readback.positionError.rawValue) "
                + "sizeReadError=\(readback.sizeError.rawValue)"
        )
    }

    private func isActive(_ request: FrameApplicationRequest) -> Bool {
        !Task.isCancelled && activeFrameApplicationRequest?.id == request.id
    }

    private func isDeterministicWriteFailure(_ error: AXError) -> Bool {
        switch error {
        case .apiDisabled,
             .attributeUnsupported,
             .illegalArgument,
             .invalidUIElement,
             .notImplemented,
             .parameterizedAttributeUnsupported:
            return true
        default:
            return false
        }
    }

    /// Rectangle 会在布局期间临时关闭该属性，避免部分应用吞掉连续的位置/尺寸写入。
    private func disableEnhancedUserInterfaceIfNeeded(
        for applicationElement: AXUIElement
    ) -> Bool {
        let current = applicationElement.copyBoolAttribute(enhancedUserInterfaceAttribute)
        guard current.value == true else {
            if current.error != .success, current.error != .attributeUnsupported {
                logger.info(
                    "window layout AX enhanced UI read skipped error=\(current.error.rawValue)"
                )
            }
            return false
        }

        let result = applicationElement.setBoolAttribute(
            enhancedUserInterfaceAttribute,
            false
        )
        guard result == .success else {
            logger.error(
                "window layout AX enhanced UI disable failed error=\(result.rawValue)"
            )
            return false
        }
        return true
    }

    /// 仅恢复由本次请求实际关闭的增强辅助功能属性。
    private func restoreEnhancedUserInterfaceIfNeeded(
        for request: FrameApplicationRequest
    ) {
        guard request.shouldRestoreEnhancedUserInterface else {
            return
        }
        let result = request.applicationElement.setBoolAttribute(
            enhancedUserInterfaceAttribute,
            true
        )
        guard result != .success else {
            return
        }
        logger.error(
            "window layout AX enhanced UI restore failed request=\(request.id) "
                + "error=\(result.rawValue)"
        )
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

    /// 将 AppKit 屏幕转换为可测试的窗口布局屏幕模型。
    private func layoutScreen(for screen: NSScreen) -> WindowLayoutScreen {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        let id: String
        if let screenNumber = screen.deviceDescription[screenNumberKey] as? NSNumber {
            id = screenNumber.stringValue
        } else {
            let frame = screen.frame.integral
            id = "frame:\(frame.origin.x),\(frame.origin.y),\(frame.width),\(frame.height)"
        }
        return WindowLayoutScreen(id: id, frame: screen.frame, visibleFrame: screen.visibleFrame)
    }

    /// 通过私有辅助功能符号取得窗口 ID；失败时当前请求仍执行，但不写入按窗口缓存。
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

    /// 读取 AXValue 包装的属性，并保留具体辅助功能错误码。
    func copyWrappedAttribute<T>(
        _ attribute: String,
        type: AXValueType
    ) -> (value: T?, error: AXError) {
        var value: AnyObject?
        let copyResult = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard copyResult == .success else {
            return (nil, copyResult)
        }
        guard
            let value,
            CFGetTypeID(value) == AXValueGetTypeID(),
            AXValueGetType(value as! AXValue) == type
        else {
            return (nil, .illegalArgument)
        }

        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }

        let success = AXValueGetValue(value as! AXValue, type, pointer)
        return success ? (pointer.pointee, .success) : (nil, .failure)
    }

    /// 读取布尔型辅助功能属性并保留错误码。
    func copyBoolAttribute(_ attribute: String) -> (value: Bool?, error: AXError) {
        var value: AnyObject?
        let copyResult = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard copyResult == .success else {
            return (nil, copyResult)
        }
        guard
            let value,
            CFGetTypeID(value) == CFBooleanGetTypeID()
        else {
            return (nil, .illegalArgument)
        }
        return (CFBooleanGetValue((value as! CFBoolean)), .success)
    }

    /// 应用 `setPointAttribute` 接收的新值，并更新相关应用运行时与 AppKit 集成状态。
    func setPointAttribute(_ attribute: String, _ value: CGPoint) -> AXError {
        var value = value
        guard let axValue = AXValueCreate(.cgPoint, &value) else {
            return .illegalArgument
        }
        return AXUIElementSetAttributeValue(self, attribute as CFString, axValue)
    }

    /// 应用 `setSizeAttribute` 接收的新值，并更新相关应用运行时与 AppKit 集成状态。
    func setSizeAttribute(_ attribute: String, _ value: CGSize) -> AXError {
        var value = value
        guard let axValue = AXValueCreate(.cgSize, &value) else {
            return .illegalArgument
        }
        return AXUIElementSetAttributeValue(self, attribute as CFString, axValue)
    }

    /// 写入布尔型辅助功能属性。
    func setBoolAttribute(_ attribute: String, _ value: Bool) -> AXError {
        AXUIElementSetAttributeValue(
            self,
            attribute as CFString,
            value ? kCFBooleanTrue : kCFBooleanFalse
        )
    }
}

/// 为窗口矩形组件提供不包含窗口内容的日志值。
private extension WindowFrameComponents {
    var logValue: String {
        var values: [String] = []
        if contains(.position) {
            values.append("position")
        }
        if contains(.size) {
            values.append("size")
        }
        return values.isEmpty ? "none" : values.joined(separator: ",")
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
