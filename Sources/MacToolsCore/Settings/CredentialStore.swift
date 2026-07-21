import Foundation

public enum CredentialKey: String, Sendable {
    case bailianAPIKey = "bailian.apiKey"
}

public protocol CredentialStore: Sendable {
    func read(_ key: CredentialKey) throws -> String?
    func save(_ value: String, for key: CredentialKey) throws
    func delete(_ key: CredentialKey) throws
}

public enum CredentialAccessError: Error, Equatable, Sendable {
    case migrationFailed
}

public actor CredentialAccessCoordinator {
    public struct LoadResult: Equatable, Sendable {
        public var value: String
        public var shouldRedactLegacy: Bool

        public init(value: String, shouldRedactLegacy: Bool) {
            self.value = value
            self.shouldRedactLegacy = shouldRedactLegacy
        }
    }

    private let store: any CredentialStore

    public init(store: any CredentialStore) {
        self.store = store
    }

    public func load(_ key: CredentialKey, fallback: String) throws -> LoadResult {
        var value = try store.read(key)
        var shouldRedactLegacy = false
        if value == nil, !fallback.isEmpty {
            try store.save(fallback, for: key)
            value = try store.read(key)
            guard value != nil else {
                throw CredentialAccessError.migrationFailed
            }
            shouldRedactLegacy = true
        } else if value != nil, !fallback.isEmpty {
            shouldRedactLegacy = true
        }
        return LoadResult(
            value: value ?? "",
            shouldRedactLegacy: shouldRedactLegacy
        )
    }

    public func save(_ value: String, for key: CredentialKey) throws {
        if value.isEmpty {
            try store.delete(key)
        } else {
            try store.save(value, for: key)
        }
    }
}
