import Foundation

public struct SuperRightClickSourceApplication: Equatable {
    public var localizedName: String?
    public var bundleIdentifier: String?
    public var processIdentifier: Int32?

    public init(
        localizedName: String?,
        bundleIdentifier: String?,
        processIdentifier: Int32?
    ) {
        self.localizedName = localizedName
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }

    public var isFinder: Bool {
        bundleIdentifier == "com.apple.finder"
    }
}

public enum SuperRightClickPresentationRoute: Equatable {
    case text
    case fileSystem
    case finderCurrentFolder
    case windowLayoutOnly
}

public enum SuperRightClickPresentationRouter {
    public static func route(
        for itemKind: ClipboardContentKind,
        sourceApplication: SuperRightClickSourceApplication?
    ) -> SuperRightClickPresentationRoute {
        switch itemKind {
        case .text, .url:
            return .text
        case .file, .folder, .imageFile:
            return .fileSystem
        case .imageData, .unknown:
            return sourceApplication?.isFinder == true
                ? .finderCurrentFolder
                : .windowLayoutOnly
        }
    }
}
