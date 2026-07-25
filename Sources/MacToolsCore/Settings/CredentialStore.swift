import Foundation

public enum CredentialKey: String, Codable, Equatable, Sendable {
    case bailianAPIKey = "bailian.apiKey"
}

public protocol LegacyCredentialReading: Sendable {
    func read(_ key: CredentialKey) throws -> String?
}

public enum CredentialAccessError: Error, Equatable, Sendable {
    case migrationVerificationFailed
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

    private let store: EncryptedCredentialStore
    private let legacyReader: any LegacyCredentialReading
    private let deviceID: String
    private let now: @Sendable () -> Date

    public init(
        store: EncryptedCredentialStore,
        legacyReader: any LegacyCredentialReading,
        deviceID: String,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.legacyReader = legacyReader
        self.deviceID = deviceID
        self.now = now
    }

    public func load(
        _ key: CredentialKey,
        fallback: String
    ) throws -> LoadResult {
        let normalizedFallback = fallback.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if let record = try store.readRecord(for: key) {
            try markMigrationCompleteIfNeeded()
            return LoadResult(
                value: record.value ?? "",
                shouldRedactLegacy: !normalizedFallback.isEmpty
            )
        }
        if try store.isMigrationComplete() {
            return LoadResult(
                value: "",
                shouldRedactLegacy: !normalizedFallback.isEmpty
            )
        }
        if !normalizedFallback.isEmpty {
            let result = try store.update(
                value: normalizedFallback,
                for: key,
                deviceID: deviceID,
                updatedAt: now()
            )
            guard result.record.value == normalizedFallback else {
                throw CredentialAccessError.migrationVerificationFailed
            }
            try? store.markMigrationComplete()
            return LoadResult(
                value: normalizedFallback,
                shouldRedactLegacy: true
            )
        }

        let legacyValue = try legacyReader.read(key)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let legacyValue, !legacyValue.isEmpty else {
            try store.markMigrationComplete()
            return LoadResult(value: "", shouldRedactLegacy: false)
        }
        let result = try store.update(
            value: legacyValue,
            for: key,
            deviceID: deviceID,
            updatedAt: now()
        )
        guard result.record.value == legacyValue else {
            throw CredentialAccessError.migrationVerificationFailed
        }
        try? store.markMigrationComplete()
        return LoadResult(value: legacyValue, shouldRedactLegacy: false)
    }

    public func loadLocal(
        _ key: CredentialKey,
        fallback: String
    ) throws -> LoadResult? {
        let shouldRedactLegacy = !fallback.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
        if let record = try store.readRecord(for: key) {
            try markMigrationCompleteIfNeeded()
            return LoadResult(
                value: record.value ?? "",
                shouldRedactLegacy: shouldRedactLegacy
            )
        }
        guard try store.isMigrationComplete() else { return nil }
        return LoadResult(
            value: "",
            shouldRedactLegacy: shouldRedactLegacy
        )
    }

    @discardableResult
    public func save(
        _ value: String,
        for key: CredentialKey
    ) throws -> CredentialEnvelopeRecord {
        let result = try store.update(
            value: value,
            for: key,
            deviceID: deviceID,
            updatedAt: now()
        )
        try? store.markMigrationComplete()
        return result.record
    }

    private func markMigrationCompleteIfNeeded() throws {
        if try !store.isMigrationComplete() {
            try store.markMigrationComplete()
        }
    }
}
