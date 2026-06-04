import Foundation

public enum RightClickEvent: Equatable {
    case pressed(atMilliseconds: Int)
    case released(atMilliseconds: Int)
    case timerFired(atMilliseconds: Int)
}

public enum RightClickDecision: Equatable {
    case none
    case allowSystemMenu
    case triggerSuperRightClick
}
