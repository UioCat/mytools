// `SuperRightClickPresentationRouter` 的超级右键领域实现。
// 负责事件决策、选区解析和动作路由，不安装系统级事件监听。

import Foundation

/// 封装 `SuperRightClickSourceApplication` 在超级右键领域中的值语义和相关操作。
public struct SuperRightClickSourceApplication: Equatable, Sendable {
    public var localizedName: String?
    public var bundleIdentifier: String?
    public var processIdentifier: Int32?

    /// 创建 `SuperRightClickSourceApplication`，保存传入依赖并建立初始状态。
    public init(
        localizedName: String?,
        bundleIdentifier: String?,
        processIdentifier: Int32?
    ) {
        self.localizedName = localizedName
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }

    public var isFinder: Bool {
        bundleIdentifier == "com.apple.finder"
    }
}

/// 描述 `SuperRightClickPresentationRoute` 在超级右键领域中可取的状态、选项或错误。
public enum SuperRightClickPresentationRoute: Equatable, Sendable {
    case text
    case fileSystem
    case finderCurrentFolder
    case windowLayoutOnly
}

/// 描述 `SuperRightClickPresentationRouter` 在超级右键领域中可取的状态、选项或错误。
public enum SuperRightClickPresentationRouter {
    /// 处理 `route` 对应的超级右键领域事件，并返回或发布处理结果。
    public static func route(
        for itemKind: ClipboardContentKind,
        sourceApplication: SuperRightClickSourceApplication?
    ) -> SuperRightClickPresentationRoute {
        switch itemKind {
        case .text, .url:
            return .text
        case .file, .folder, .imageFile:
            return .fileSystem
        case .imageData, .unknown:
            return sourceApplication?.isFinder == true
                ? .finderCurrentFolder
                : .windowLayoutOnly
        }
    }
}
