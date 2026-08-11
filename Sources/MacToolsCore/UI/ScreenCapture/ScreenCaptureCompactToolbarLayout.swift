// 截图编辑器紧凑工具栏布局，固定 40pt 控件节奏并提供可执行的窄宽度约束。

import SwiftUI

public struct ScreenCaptureCompactToolbarLayout: Layout {
    public init() {}

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        CGSize(
            width: ScreenCaptureEditorToolbarMetrics.contentWidth(
                controlCount: subviews.count
            ),
            height: ScreenCaptureEditorToolbarMetrics.controlSize
                + ScreenCaptureEditorToolbarMetrics.compactPadding * 2
        )
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let metrics = ScreenCaptureEditorToolbarMetrics.self
        let contentWidth = metrics.contentWidth(controlCount: subviews.count)
        var centerX = bounds.midX - contentWidth / 2
            + metrics.compactPadding
            + metrics.controlSize / 2
        let controlProposal = ProposedViewSize(
            width: metrics.controlSize,
            height: metrics.controlSize
        )

        for subview in subviews {
            subview.place(
                at: CGPoint(x: centerX, y: bounds.midY),
                anchor: .center,
                proposal: controlProposal
            )
            centerX += metrics.controlSize + metrics.compactSpacing
        }
    }
}
