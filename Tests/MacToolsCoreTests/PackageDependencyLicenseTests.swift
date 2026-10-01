import Foundation
import XCTest

final class PackageDependencyLicenseTests: XCTestCase {
    func testCopiesBothLicensesWithoutChangingText() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let build = root.appendingPathComponent("build")
        let resources = root.appendingPathComponent("App/Contents/Resources")
        let grdb = build.appendingPathComponent("checkouts/GRDB.swift/LICENSE")
        let sparkle = build.appendingPathComponent("artifacts/sparkle/Sparkle/LICENSE")
        for file in [grdb, sparkle] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try Data("synthetic GRDB attribution\n".utf8).write(to: grdb)
        try Data("synthetic Sparkle attribution\n".utf8).write(to: sparkle)

        XCTAssertEqual(try run(build: build, resources: resources), 0)
        XCTAssertEqual(try Data(contentsOf: resources.appendingPathComponent("ThirdPartyLicenses/GRDB.txt")), try Data(contentsOf: grdb))
        XCTAssertEqual(try Data(contentsOf: resources.appendingPathComponent("ThirdPartyLicenses/Sparkle.txt")), try Data(contentsOf: sparkle))
    }

    func testMissingLicenseFailsBeforeProducingIncompleteAttributions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let resources = root.appendingPathComponent("resources")
        XCTAssertNotEqual(try run(build: root.appendingPathComponent("missing"), resources: resources), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: resources.path))
    }

    private func run(build: URL, resources: URL) throws -> Int32 {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [repository.appendingPathComponent("scripts/package_dependency_licenses.sh").path, build.path, resources.path]
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
