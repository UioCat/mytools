import Foundation

public struct RightClickStateMachine {
    private let thresholdMilliseconds: Int
    private var pressStartMilliseconds: Int?
    private var didTrigger = false

    public init(thresholdMilliseconds: Int) {
        self.thresholdMilliseconds = thresholdMilliseconds
    }

    public mutating func handle(_ event: RightClickEvent) -> RightClickDecision {
        switch event {
        case let .pressed(atMilliseconds):
            pressStartMilliseconds = atMilliseconds
            didTrigger = false
            return .none

        case .released:
            let shouldAllowSystemMenu = pressStartMilliseconds != nil && !didTrigger
            pressStartMilliseconds = nil
            didTrigger = false
            return shouldAllowSystemMenu ? .allowSystemMenu : .none

        case let .timerFired(atMilliseconds):
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

public enum RightClickEventRoute: Equatable {
    case passOriginalEvent
    case suppressOriginalEvent
    case suppressAndReplaySystemRightClick
    case suppressAndTriggerSuperRightClick

    public var shouldSuppressOriginalEvent: Bool {
        self != .passOriginalEvent
    }
}

public struct RightClickGestureRouter {
    private var stateMachine: RightClickStateMachine

    public init(thresholdMilliseconds: Int) {
        self.stateMachine = RightClickStateMachine(thresholdMilliseconds: thresholdMilliseconds)
    }

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
            return stateMachine.handle(event) == .allowSystemMenu
                ? .suppressAndReplaySystemRightClick
                : .suppressOriginalEvent
        }
    }
}
