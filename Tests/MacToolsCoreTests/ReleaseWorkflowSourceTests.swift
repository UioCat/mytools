import Foundation
import XCTest

final class ReleaseWorkflowSourceTests: XCTestCase {
    func testReleaseWorkflowGeneratesSignedAppcastFromIsolatedInput() throws {
        let workflow = try sourceFile(".github/workflows/release.yml")

        XCTAssertTrue(workflow.contains("SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}"))
        XCTAssertTrue(workflow.contains("APPCAST_INPUT_DIR"))
        XCTAssertTrue(workflow.contains("generate_appcast"))
        XCTAssertTrue(workflow.contains("--ed-key-file -"))
        XCTAssertTrue(workflow.contains("--versions \"$GITHUB_RUN_NUMBER\""))
        XCTAssertTrue(workflow.contains("--download-url-prefix"))
        XCTAssertTrue(workflow.contains("sparkle:edSignature"))
        XCTAssertTrue(workflow.contains("sparkle-signatures"))
        XCTAssertTrue(workflow.contains("sign_update"))
        XCTAssertTrue(workflow.contains("--verify"))
    }

    func testReleaseWorkflowPublishesAndVerifiesAllUpdateAssets() throws {
        let workflow = try sourceFile(".github/workflows/release.yml")

        XCTAssertTrue(workflow.contains("dist/*.dmg"))
        XCTAssertTrue(workflow.contains("dist/*.sha256"))
        XCTAssertTrue(workflow.contains("dist/appcast.xml"))
        XCTAssertTrue(workflow.contains("--pattern \"appcast.xml\""))
        XCTAssertTrue(workflow.contains("releases/latest/download/appcast.xml"))
        XCTAssertTrue(workflow.contains("--draft=false"))
    }

    private func sourceFile(_ path: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}
