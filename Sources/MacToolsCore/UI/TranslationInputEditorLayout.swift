// `TranslationInputEditorLayout` 的 SwiftUI 展示层实现。
// 负责视图状态、布局和用户操作回调，不直接拥有系统集成生命周期。

import CoreGraphics

/// 封装 `TranslationInputEditorLayout` 在 SwiftUI 展示层中的值语义和相关操作。
public struct TranslationInputEditorLayout: Equatable, Sendable {
    public let placeholderLeadingPadding: CGFloat
    public let placeholderTopPadding: CGFloat
    public let textContainerWidthInset: CGFloat
    public let textContainerHeightInset: CGFloat
    public let lineFragmentPadding: CGFloat

    /// 创建 `TranslationInputEditorLayout`，保存传入依赖并建立初始状态。
    public init(
        placeholderLeadingPadding: CGFloat,
        placeholderTopPadding: CGFloat,
        textContainerWidthInset: CGFloat,
        textContainerHeightInset: CGFloat,
        lineFragmentPadding: CGFloat
    ) {
        self.placeholderLeadingPadding = placeholderLeadingPadding
        self.placeholderTopPadding = placeholderTopPadding
        self.textContainerWidthInset = textContainerWidthInset
        self.textContainerHeightInset = textContainerHeightInset
        self.lineFragmentPadding = lineFragmentPadding
    }

    public static let standard = TranslationInputEditorLayout(
        placeholderLeadingPadding: 6,
        placeholderTopPadding: 8,
        textContainerWidthInset: 6,
        textContainerHeightInset: 8,
        lineFragmentPadding: 0
    )

    public var caretLeadingOffset: CGFloat {
        textContainerWidthInset + lineFragmentPadding
    }

    public var placeholderLeadingOffset: CGFloat {
        placeholderLeadingPadding
    }
}

/// 封装 `TranslationWorkspaceLayout` 在 SwiftUI 展示层中的值语义和相关操作。
public struct TranslationWorkspaceLayout: Equatable, Sendable {
    public let inputEditorMinimumHeight: CGFloat
    public let outputEditorMinimumHeight: CGFloat

    /// 创建 `TranslationWorkspaceLayout`，保存传入依赖并建立初始状态。
    public init(
        inputEditorMinimumHeight: CGFloat,
        outputEditorMinimumHeight: CGFloat
    ) {
        self.inputEditorMinimumHeight = inputEditorMinimumHeight
        self.outputEditorMinimumHeight = outputEditorMinimumHeight
    }

    public static let standard = TranslationWorkspaceLayout(
        inputEditorMinimumHeight: 120,
        outputEditorMinimumHeight: 150
    )
}
