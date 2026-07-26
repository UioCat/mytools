// `RightClickEvent` 的超级右键领域实现。
// 负责事件决策、选区解析和动作路由，不安装系统级事件监听。

import Foundation

/// 描述 `RightClickEvent` 在超级右键领域中可取的状态、选项或错误。
public enum RightClickEvent: Equatable {
    case pressed(atMilliseconds: Int)
    case released(atMilliseconds: Int)
    case timerFired(atMilliseconds: Int)
}

/// 描述 `RightClickDecision` 在超级右键领域中可取的状态、选项或错误。
public enum RightClickDecision: Equatable {
    case none
    case allowSystemMenu
    case triggerSuperRightClick
}
