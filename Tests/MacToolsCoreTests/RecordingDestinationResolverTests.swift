import Foundation
import XCTest
@testable import MacToolsCore

final class RecordingDestinationResolverTests: XCTestCase {
    func testDestinationUsesDownloadsAndIncrementsExistingFilename() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let timestamp = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 12,
            hour: 10,
            minute: 30
        )))
        let resolver = RecordingDestinationResolver(
            directory: directory,
            now: timestamp,
            timeZone: calendar.timeZone
        )

        let first = try resolver.nextURL()
        try Data().write(to: first)

        XCTAssertEqual(first.lastPathComponent, "MacTools Recording 2026-07-12 10.30.00.mp4")
        XCTAssertEqual(try resolver.nextURL().lastPathComponent, "MacTools Recording 2026-07-12 10.30.00 2.mp4")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingDestinationResolverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
