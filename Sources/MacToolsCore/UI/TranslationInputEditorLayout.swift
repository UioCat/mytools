import CoreGraphics

public struct TranslationInputEditorLayout: Equatable {
    public let placeholderLeadingPadding: CGFloat
    public let placeholderTopPadding: CGFloat
    public let textContainerWidthInset: CGFloat
    public let textContainerHeightInset: CGFloat
    public let lineFragmentPadding: CGFloat

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
