import Foundation

public enum SuperPanelPreviewLineLimitPolicy {
    public static func lineLimit(
        for kind: SuperPanelKind,
        row: SuperPanelPreviewRow
    ) -> Int? {
        switch kind {
        case .text, .textTransit:
            return nil
        case .fileSystem, .windowLayout:
            return 2
        }
    }
}
