import Foundation
import XCTest

final class CodeOrganizationSourceTests: XCTestCase {
    func testSettingsViewRemainsACompactCompositionRoot() throws {
        let settingsView = try sourceFile("Sources/MacToolsCore/UI/Settings/SettingsView.swift")

        XCTAssertLessThanOrEqual(settingsView.lineCount, 400)
        XCTAssertTrue(settingsView.contains("public struct SettingsView: View"))
        XCTAssertFalse(settingsView.contains("struct SyncSettingsEditor: View"))
        XCTAssertFalse(settingsView.contains("struct TranslationSettingsEditor: View"))
    }

    func testClipboardRepositoryKeepsStorageHelpersInDedicatedFiles() throws {
        let repository = try sourceFile(
            "Sources/MacToolsCore/Storage/ClipboardRepository.swift"
        )
        let garbageCollector = try sourceFile(
            "Sources/MacToolsCore/Storage/PayloadGarbageCollector.swift"
        )
        let recordMapping = try sourceFile(
            "Sources/MacToolsCore/Storage/ClipboardItem+FetchableRecord.swift"
        )

        XCTAssertLessThan(repository.lineCount, 1_000)
        XCTAssertFalse(repository.contains("final class PayloadGarbageCollector"))
        XCTAssertFalse(repository.contains("extension ClipboardItem: FetchableRecord"))
        XCTAssertTrue(garbageCollector.contains("final class PayloadGarbageCollector"))
        XCTAssertTrue(recordMapping.contains("extension ClipboardItem: FetchableRecord"))
    }

    func testAppEnvironmentKeepsExecutionWorkersInDedicatedFile() throws {
        let environment = try sourceFile("Sources/MacTools/Application/AppEnvironment.swift")
        let workers = try sourceFile("Sources/MacTools/Application/AppEnvironmentWorkers.swift")

        XCTAssertLessThan(environment.lineCount, 1_000)
        XCTAssertFalse(environment.contains("actor ClipboardPollingWorker"))
        XCTAssertFalse(environment.contains("actor AppMaintenanceWorker"))
        XCTAssertFalse(environment.contains("final class PasteActivationAttempt"))
        XCTAssertTrue(workers.contains("actor ClipboardPollingWorker"))
        XCTAssertTrue(workers.contains("actor AppMaintenanceWorker"))
        XCTAssertTrue(workers.contains("final class PasteActivationAttempt"))
    }

    func testUIFilesDoNotDependOnConcreteStorageImplementations() throws {
        let uiDirectory = repositoryRoot.appendingPathComponent(
            "Sources/MacToolsCore/UI",
            isDirectory: true
        )
        let forbiddenReferences = [
            "import GRDB",
            "ClipboardDatabase",
            "ClipboardRepository",
            "DriveSyncStore",
            "PayloadStore",
            "PreferenceRepository",
            "DeviceOverrideRepository",
            "EncryptedCredentialStore"
        ]
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: uiDirectory,
                includingPropertiesForKeys: nil
            )
        )

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            for forbiddenReference in forbiddenReferences {
                XCTAssertFalse(
                    source.contains(forbiddenReference),
                    "\(fileURL.path) must not reference \(forbiddenReference)"
                )
            }
        }
    }

    private func sourceFile(_ path: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private extension String {
    var lineCount: Int {
        split(separator: "\n", omittingEmptySubsequences: false).count
    }
}
