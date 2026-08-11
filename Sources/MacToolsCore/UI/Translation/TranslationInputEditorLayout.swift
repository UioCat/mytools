// 翻译输入编辑器的占位文本和内边距几何策略。
// 提供可测试的布局计算，不依赖具体 NSTextView 生命周期。

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

    /// 短内容在可见编辑区内垂直居中；内容接近或超过可见高度时保留最小边距。
    public func verticalContentInset(
        viewportHeight: CGFloat,
        contentHeight: CGFloat
    ) -> CGFloat {
        guard viewportHeight.isFinite,
              contentHeight.isFinite,
              viewportHeight > 0,
              contentHeight >= 0 else {
            return textContainerHeightInset
        }

        return max(
            textContainerHeightInset,
            (viewportHeight - contentHeight) / 2
        )
    }

    /// 返回与当前 inset 匹配的文档高度，避免短内容切换为长内容后保留旧滚动空白。
    public func documentHeight(
        viewportHeight: CGFloat,
        contentHeight: CGFloat
    ) -> CGFloat {
        guard viewportHeight.isFinite,
              contentHeight.isFinite,
              viewportHeight >= 0,
              contentHeight >= 0 else {
            return max(0, viewportHeight.isFinite ? viewportHeight : 0)
        }

        let verticalInset = verticalContentInset(
            viewportHeight: viewportHeight,
            contentHeight: contentHeight
        )
        return max(
            viewportHeight,
            contentHeight + 2 * verticalInset
        )
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
