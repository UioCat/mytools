// `RightClickStateMachine` 的超级右键领域实现。
// 负责事件决策、选区解析和动作路由，不安装系统级事件监听。

import Foundation

/// 维护一次右键按压的开始时间和长按触发状态，用于区分系统短按与超级右键长按。
public struct RightClickStateMachine {
    private let thresholdMilliseconds: Int
    private var pressStartMilliseconds: Int?
    private var didTrigger = false

    /// 使用给定长按阈值创建空闲状态机。
    public init(thresholdMilliseconds: Int) {
        self.thresholdMilliseconds = thresholdMilliseconds
    }

    /// 推进一次右键手势并返回调用方需要执行的决策。
    public mutating func handle(_ event: RightClickEvent) -> RightClickDecision {
        switch event {
        case let .pressed(atMilliseconds):
            // 新按压会开启独立手势，并清除上一轮的触发标记。
            pressStartMilliseconds = atMilliseconds
            didTrigger = false
            return .none

        case let .released(atMilliseconds):
            // 抬起可能先于主线程定时器到达；此时仍应按真实持续时间确认长按，不得误回放系统菜单。
            let decision: RightClickDecision
            if didTrigger {
                decision = .none
            } else if let pressStartMilliseconds,
                      atMilliseconds - pressStartMilliseconds >= thresholdMilliseconds {
                decision = .triggerSuperRightClick
            } else if pressStartMilliseconds != nil {
                decision = .allowSystemMenu
            } else {
                decision = .none
            }
            pressStartMilliseconds = nil
            didTrigger = false
            return decision

        case let .timerFired(atMilliseconds):
            // 定时器可能重复触发或晚于抬起到达，必须同时校验手势仍有效且尚未消费。
            guard let pressStartMilliseconds, !didTrigger else {
                return .none
            }

            guard atMilliseconds - pressStartMilliseconds >= thresholdMilliseconds else {
                return .none
            }

            didTrigger = true
            return .triggerSuperRightClick
        }
    }
}

/// 描述 `RightClickEventRoute` 在超级右键领域中可取的状态、选项或错误。
public enum RightClickEventRoute: Equatable {
    case passOriginalEvent
    case suppressOriginalEvent
    case suppressAndReplaySystemRightClick
    case suppressAndTriggerSuperRightClick

    public var shouldSuppressOriginalEvent: Bool {
        self != .passOriginalEvent
    }
}

/// 把纯状态机决策转换为 event tap 可执行的抑制、回放或长按触发路由。
public struct RightClickGestureRouter {
    private var stateMachine: RightClickStateMachine

    /// 创建 `RightClickGestureRouter`，保存传入依赖并建立初始状态。
    public init(thresholdMilliseconds: Int) {
        self.stateMachine = RightClickStateMachine(thresholdMilliseconds: thresholdMilliseconds)
    }

    /// 路由右键事件；短按抑制原事件后回放系统右键，长按则只触发超级右键。
    public mutating func handle(_ event: RightClickEvent) -> RightClickEventRoute {
        switch event {
        case .pressed:
            _ = stateMachine.handle(event)
            return .suppressOriginalEvent
        case .timerFired:
            return stateMachine.handle(event) == .triggerSuperRightClick
                ? .suppressAndTriggerSuperRightClick
                : .suppressOriginalEvent
        case .released:
            switch stateMachine.handle(event) {
            case .allowSystemMenu:
                return .suppressAndReplaySystemRightClick
            case .triggerSuperRightClick:
                return .suppressAndTriggerSuperRightClick
            case .none:
                return .suppressOriginalEvent
            }
        }
    }
}
