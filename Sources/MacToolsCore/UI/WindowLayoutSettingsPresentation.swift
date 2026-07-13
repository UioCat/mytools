import CoreGraphics

enum SettingsPageColumnArrangement: Equatable {
    case twoColumns
    case stacked
}

enum SettingsPageLayout {
    static let primaryColumnMinimumWidth: CGFloat = 320
    static let secondaryColumnMinimumWidth: CGFloat = 360
    static let columnSpacing: CGFloat = 14
    static let minimumTwoColumnContentWidth = primaryColumnMinimumWidth + secondaryColumnMinimumWidth + columnSpacing

    static func columnArrangement(for availableWidth: CGFloat) -> SettingsPageColumnArrangement {
        availableWidth >= minimumTwoColumnContentWidth ? .twoColumns : .stacked
    }
}

enum WindowLayoutPreviewGeometry {
    static func screenFrame(in bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: 1, dy: 1)
    }

    static func targetFrame(for segment: WindowLayoutPreviewSegment, in bounds: CGRect) -> CGRect {
        let placementArea = screenFrame(in: bounds).insetBy(dx: 2, dy: 2)

        return CGRect(
            x: placementArea.minX + placementArea.width * segment.x,
            y: placementArea.minY + placementArea.height * segment.y,
            width: placementArea.width * segment.width,
            height: placementArea.height * segment.height
        )
    }
}
