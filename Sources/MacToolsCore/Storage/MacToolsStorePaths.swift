import Foundation

public struct MacToolsStorePaths: Equatable {
    public let supportDirectory: URL
    private let storeDirectoryOverride: URL?

    public init(supportDirectory: URL, storeDirectoryOverride: URL? = nil) {
        self.supportDirectory = supportDirectory
        self.storeDirectoryOverride = storeDirectoryOverride
    }

    public var storeDirectory: URL {
        storeDirectoryOverride
            ?? supportDirectory.appendingPathComponent("Store", isDirectory: true)
    }

    public var databaseURL: URL {
        storeDirectory.appendingPathComponent("mactools.sqlite3")
    }

    public var payloadsDirectory: URL {
        storeDirectory.appendingPathComponent("Payloads", isDirectory: true)
    }

    public func runtimePayloadsDirectory(
        persistentStoreAvailable: Bool,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> URL {
        guard !persistentStoreAvailable else { return payloadsDirectory }
        return temporaryDirectory.appendingPathComponent(
            "MacTools-IsolatedFallback-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    public var legacyDatabaseURL: URL {
        supportDirectory.appendingPathComponent("Clipboard.sqlite")
    }

    public var legacyPayloadsDirectory: URL {
        supportDirectory.appendingPathComponent("ClipboardCache", isDirectory: true)
    }

    public var legacySettingsURL: URL {
        supportDirectory.appendingPathComponent("settings.json")
    }
}
