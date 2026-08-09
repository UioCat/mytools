import Foundation
import XCTest

final class AnonymousSigningDerivationTests: XCTestCase {
    func testDerivationIsDeterministicAndKeepsPrivateOutputOwnerOnly() throws {
        let temporaryRoot = try makeTemporaryDirectory(mode: 0o700)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let firstDirectory = temporaryRoot.appendingPathComponent("first", isDirectory: true)
        let secondDirectory = temporaryRoot.appendingPathComponent("second", isDirectory: true)
        try createDirectory(firstDirectory, mode: 0o700)
        try createDirectory(secondDirectory, mode: 0o700)

        let firstOutput = firstDirectory.appendingPathComponent("private.pem")
        let secondOutput = secondDirectory.appendingPathComponent("private.pem")
        let publicTestRoot = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

        let firstResult = try runDerivation(root: publicTestRoot, output: firstOutput)
        let secondResult = try runDerivation(root: publicTestRoot, output: secondOutput)

        XCTAssertEqual(firstResult.status, 0, firstResult.standardError)
        XCTAssertEqual(secondResult.status, 0, secondResult.standardError)
        XCTAssertEqual(try Data(contentsOf: firstOutput), try Data(contentsOf: secondOutput))
        XCTAssertEqual(try permissions(of: firstOutput), 0o600)
        XCTAssertEqual(try permissions(of: secondOutput), 0o600)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstOutput.path + ".der"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondOutput.path + ".der"))
    }

    func testDerivationRejectsInvalidSparkleRootWithoutLeavingPrivateOutput() throws {
        let temporaryRoot = try makeTemporaryDirectory(mode: 0o700)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let output = temporaryRoot.appendingPathComponent("private.pem")
        let result = try runDerivation(root: "not-a-sparkle-seed", output: output)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.standardError.contains("32-byte Sparkle seed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path + ".der"))
    }

    func testDerivationRejectsOutputDirectoryAccessibleByOtherUsers() throws {
        let temporaryRoot = try makeTemporaryDirectory(mode: 0o755)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let output = temporaryRoot.appendingPathComponent("private.pem")
        let result = try runDerivation(
            root: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            output: output
        )

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.standardError.contains("mode 0700"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    private func runDerivation(
        root: String,
        output: URL
    ) throws -> (status: Int32, standardError: String) {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [derivationScript.path, output.path]
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["SPARKLE_PRIVATE_KEY": root],
            uniquingKeysWith: { _, newValue in newValue }
        )
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()
        _ = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
        return (
            process.terminationStatus,
            String(decoding: errorData, as: UTF8.self)
        )
    }

    private func makeTemporaryDirectory(mode: Int) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacToolsSigningTests-\(UUID().uuidString)", isDirectory: true)
        try createDirectory(directory, mode: mode)
        return directory
    }

    private func createDirectory(_ directory: URL, mode: Int) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: NSNumber(value: mode)]
        )
    }

    private func permissions(of file: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        return permissions.intValue & 0o777
    }

    private var derivationScript: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/signing/derive_anonymous_signing_private_key.sh")
    }
}
