import Foundation
import XCTest
@testable import MacToolsCore

final class CredentialAccessCoordinatorTests: XCTestCase {
    func testQueuedUserSaveWinsAfterBlockedLegacyMigration() async throws {
        let store = BlockingCredentialStore()
        let access = CredentialAccessCoordinator(store: store)
        let loadTask = Task {
            try await access.load(.bailianAPIKey, fallback: "legacy-value")
        }

        XCTAssertEqual(store.firstReadStarted.wait(timeout: .now() + 1), .success)
        let saveTask = Task {
            try await access.save("new-value", for: .bailianAPIKey)
        }
        store.releaseFirstRead.signal()

        let result = try await loadTask.value
        try await saveTask.value

        XCTAssertEqual(result.value, "legacy-value")
        XCTAssertTrue(result.shouldRedactLegacy)
        XCTAssertEqual(store.currentValue(), "new-value")
    }

    func testEmptySaveDeletesCredential() async throws {
        let store = BlockingCredentialStore(initialValue: "configured", blocksFirstRead: false)
        let access = CredentialAccessCoordinator(store: store)

        try await access.save("", for: .bailianAPIKey)

        XCTAssertNil(store.currentValue())
    }
}

private final class BlockingCredentialStore: CredentialStore, @unchecked Sendable {
    let firstReadStarted = DispatchSemaphore(value: 0)
    let releaseFirstRead = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var value: String?
    private var blocksFirstRead: Bool

    init(initialValue: String? = nil, blocksFirstRead: Bool = true) {
        self.value = initialValue
        self.blocksFirstRead = blocksFirstRead
    }

    func read(_ key: CredentialKey) throws -> String? {
        lock.lock()
        let shouldBlock = blocksFirstRead
        blocksFirstRead = false
        lock.unlock()
        if shouldBlock {
            firstReadStarted.signal()
            _ = releaseFirstRead.wait(timeout: .now() + 2)
        }
        return currentValue()
    }

    func save(_ value: String, for key: CredentialKey) throws {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func delete(_ key: CredentialKey) throws {
        lock.lock()
        value = nil
        lock.unlock()
    }

    func currentValue() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
