import Foundation
import XCTest

final class PackageAppScriptTests: XCTestCase {
    func testPackageScriptDeclaresFinderAppleEventsUsageDescription() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = repositoryRoot.appendingPathComponent("scripts/package_app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("<key>NSAppleEventsUsageDescription</key>"))
        XCTAssertTrue(script.contains("<string>用于读取访达当前窗口目录，以显示超级右键的目录操作。</string>"))
    }

    func testPackageScriptDeclaresAndCopiesApplicationIcon() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = repositoryRoot.appendingPathComponent("scripts/package_app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(
            script.contains("Sources/MacTools/Resources/AppIcon.icns")
        )
        XCTAssertTrue(script.contains("<key>CFBundleIconFile</key>"))
        XCTAssertTrue(script.contains("<string>AppIcon.icns</string>"))
    }

    func testPackageScriptDoesNotRequireCloudKitEntitlementsOrProvisioningProfile() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = repositoryRoot.appendingPathComponent("scripts/package_app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertFalse(script.contains("MACOS_ENABLE_CLOUDKIT"))
        XCTAssertFalse(script.contains("MacToolsCloudSyncAvailable"))
        XCTAssertFalse(script.contains("MACOS_ICLOUD_CONTAINER_ID"))
        XCTAssertFalse(script.contains("MACOS_PROVISIONING_PROFILE"))
        XCTAssertFalse(script.contains("com.apple.developer.icloud"))
    }

    func testPackageScriptSeparatesStableAndDevelopmentSigning() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = repositoryRoot.appendingPathComponent("scripts/package_app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("MACOS_SIGNING_MODE"))
        XCTAssertTrue(script.contains("stable"))
        XCTAssertTrue(script.contains("development"))
        XCTAssertTrue(script.contains("BUNDLE_ID=\"local.mactools.mvp\""))
        XCTAssertTrue(script.contains("BUNDLE_ID=\"local.mactools.development\""))
        XCTAssertTrue(script.contains("CFBundleDisplayName"))
        XCTAssertTrue(script.contains("MacToolsReleaseSigning.pem"))
        XCTAssertTrue(script.contains("25A3263958804C6D9429EB51B97BA2B16CA1FB67"))
        XCTAssertTrue(
            script.contains("D098182A8CFA254D9834F5E0E7911C39418080D38B1AC921E8F90E90DDE3E157")
        )
        XCTAssertTrue(script.contains("certificate leaf = H"))
        XCTAssertTrue(script.contains("verify_stable_component_signature"))
        XCTAssertTrue(script.contains("--extract-certificates=\"$EMBEDDED_CERTIFICATE_PREFIX\""))
        XCTAssertTrue(script.contains("stable signing identity is unavailable"))
        XCTAssertTrue(script.contains("--sign \"$EXPECTED_CERTIFICATE_SHA1\""))
        XCTAssertTrue(script.contains("development signing uses an isolated ad-hoc identity"))
        XCTAssertTrue(script.contains("--sign -"))
        XCTAssertFalse(script.contains("MACOS_FORCE_ADHOC_SIGNING"))
        XCTAssertFalse(script.contains("MACOS_BUNDLE_ID"))
        XCTAssertFalse(script.contains("/Developer ID Application|Apple Development|Mac Developer/"))
    }

    func testNoTeamIDSigningDisablesOnlyMainAppLibraryValidation() throws {
        let entitlementsURL = repositoryRoot.appendingPathComponent(
            "scripts/signing/MacToolsNoTeamID.entitlements"
        )
        let entitlements = try String(contentsOf: entitlementsURL, encoding: .utf8)
        let script = try packageScript()

        XCTAssertTrue(entitlements.contains("com.apple.security.cs.disable-library-validation"))
        XCTAssertFalse(entitlements.contains("com.apple.security.app-sandbox"))
        XCTAssertFalse(entitlements.contains("com.apple.developer"))
        XCTAssertTrue(script.contains("MAIN_APP_ENTITLEMENTS"))
        XCTAssertTrue(script.contains("--entitlements \"$MAIN_APP_ENTITLEMENTS\""))
    }

    func testRepositoryContainsAnonymousPublicSigningCertificate() throws {
        let certificateURL = repositoryRoot.appendingPathComponent(
            "scripts/signing/MacToolsReleaseSigning.pem"
        )
        let certificate = try String(contentsOf: certificateURL, encoding: .utf8)

        XCTAssertTrue(certificate.contains("-----BEGIN CERTIFICATE-----"))
        XCTAssertFalse(certificate.localizedCaseInsensitiveContains("@"))

        let subject = try certificateSubject(at: certificateURL)
        XCTAssertEqual(subject, "subject=CN=MacTools Release Signing")
    }

    func testRebuildScriptUsesCanonicalStableInstallationAndIsolatedDevelopmentIdentity() throws {
        let script = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/rebuild_and_run_app.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(script.contains("SIGNING_MODE=\"${MACOS_SIGNING_MODE:-stable}\""))
        XCTAssertTrue(script.contains("/Applications/MacTools.app"))
        XCTAssertTrue(script.contains("local.mactools.development"))
        XCTAssertTrue(script.contains("target_app_process_ids"))
        XCTAssertTrue(script.contains("ps -p \"$process_id\" -o command="))
        XCTAssertTrue(script.contains("process_command\" == \"$executable_path\""))
        XCTAssertFalse(script.contains("pkill -x \"$APP_NAME\""))
        XCTAssertTrue(script.contains("CONFLICTING_APP_EXEC"))
        XCTAssertTrue(script.contains("ensure_no_conflicting_app"))
        XCTAssertTrue(script.contains("refusing to run both identities concurrently"))
        XCTAssertTrue(script.contains("MACOS_SIGNING_MODE=\"$SIGNING_MODE\""))
        XCTAssertFalse(script.contains("swift run"))
        XCTAssertFalse(script.contains("tccutil reset"))
    }

    func testSuperRightClickDiagnosticsInspectCanonicalInstalledAppByDefault() throws {
        let script = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "scripts/diagnose_super_right_click.sh"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(script.contains("/Applications/MacTools.app"))
        XCTAssertTrue(script.contains("MACTOOLS_APP_DIR"))
        XCTAssertFalse(script.contains("APP_DIR=\"$ROOT_DIR/build/MacTools.app\""))
    }

    func testPackageScriptEmbedsAndSignsSparkleComponents() throws {
        let script = try packageScript()

        XCTAssertTrue(script.contains("FRAMEWORKS_DIR=\"$CONTENTS_DIR/Frameworks\""))
        XCTAssertTrue(script.contains("release/Sparkle.framework"))
        XCTAssertTrue(
            script.contains("install_name_tool -add_rpath '@executable_path/../Frameworks'")
        )
        XCTAssertTrue(
            script.contains("SPARKLE_VERSION_DIR=\"$SPARKLE_FRAMEWORK/Versions/Current\"")
        )
        XCTAssertTrue(script.contains("$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"))
        XCTAssertTrue(script.contains("$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"))
        XCTAssertTrue(script.contains("$SPARKLE_VERSION_DIR/Autoupdate"))
        XCTAssertTrue(script.contains("$SPARKLE_VERSION_DIR/Updater.app"))
        XCTAssertFalse(script.contains("codesign --force --deep"))
    }

    func testPackageScriptDeclaresSecureSparkleDefaults() throws {
        let script = try packageScript()

        XCTAssertTrue(script.contains("<key>SUFeedURL</key>"))
        XCTAssertTrue(script.contains("<key>SUPublicEDKey</key>"))
        XCTAssertTrue(script.contains("<key>SUEnableAutomaticChecks</key>"))
        XCTAssertTrue(script.contains("<key>SUAutomaticallyUpdate</key>"))
        XCTAssertTrue(script.contains("<key>SUVerifyUpdateBeforeExtraction</key>"))
        XCTAssertTrue(script.contains("<key>SURequireSignedFeed</key>"))
        XCTAssertTrue(script.contains("Delete :SUFeedURL"))
        XCTAssertTrue(script.contains("Delete :SUPublicEDKey"))
        XCTAssertTrue(script.contains("Set :SUEnableAutomaticChecks false"))
        XCTAssertFalse(script.contains("SPARKLE_PRIVATE_KEY"))
    }

    func testPackageScriptDerivesDefaultBuildNumberFromApplicationVersion() throws {
        let script = try packageScript()

        XCTAssertTrue(
            script.contains(
                "BUILD_NUMBER=\"${MACOS_BUILD_NUMBER:-$(\"$BUILD_NUMBER_SCRIPT\" \"$APP_VERSION\")}\""
            )
        )
        XCTAssertFalse(script.contains("BUILD_NUMBER=\"${MACOS_BUILD_NUMBER:-1}\""))
    }

    func testBuildNumberScriptProducesMonotonicPostMigrationVersions() throws {
        XCTAssertTrue(
            FileManager.default.isExecutableFile(
                atPath: repositoryRoot.appendingPathComponent("scripts/macos_build_number.sh").path
            )
        )
        let currentDevelopmentBuild = try derivedBuildNumber(for: "0.3.0")
        XCTAssertEqual(currentDevelopmentBuild, "1000.3.0")
        XCTAssertGreaterThan(
            Int(currentDevelopmentBuild.split(separator: ".")[0]) ?? 0,
            7
        )
        XCTAssertEqual(try derivedBuildNumber(for: "0.2.1"), "1000.2.1")
        XCTAssertEqual(try derivedBuildNumber(for: "1.2.3"), "1001.2.3")
        XCTAssertEqual(try derivedBuildNumber(for: "2"), "1002.0.0")
    }

    func testBuildNumberScriptRejectsComponentsOutsideBundleVersionLimits() throws {
        let result = try runBuildNumberScript(version: "0.100.0")

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.standardError.contains("minor and patch versions must be at most 99"))
    }

    func testPackageScriptRemovesPersonalBuildPathsFromReleaseBinary() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = repositoryRoot.appendingPathComponent("scripts/package_app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("mktemp -d"))
        XCTAssertTrue(script.contains("--scratch-path \"$BUILD_DIR\""))
        XCTAssertTrue(script.contains("-file-prefix-map"))
        XCTAssertTrue(script.contains("-debug-prefix-map"))
        XCTAssertTrue(script.contains("\"$ROOT_DIR=.\""))
        XCTAssertFalse(script.contains("BUILD_DIR=\"$ROOT_DIR/.build/release\""))
    }

    private func packageScript() throws -> String {
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/package_app.sh"),
            encoding: .utf8
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func derivedBuildNumber(for version: String) throws -> String {
        let result = try runBuildNumberScript(version: version)
        XCTAssertEqual(result.status, 0, result.standardError)
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func certificateSubject(at certificateURL: URL) throws -> String {
        let process = Process()
        let standardOutput = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = [
            "x509",
            "-in", certificateURL.path,
            "-noout",
            "-subject",
            "-nameopt", "RFC2253",
        ]
        process.standardOutput = standardOutput

        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return String(
            decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "subject= ", with: "subject=")
    }

    private func runBuildNumberScript(
        version: String
    ) throws -> (status: Int32, standardOutput: String, standardError: String) {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            repositoryRoot.appendingPathComponent("scripts/macos_build_number.sh").path,
            version,
        ]
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()

        return (
            process.terminationStatus,
            String(
                decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ),
            String(
                decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
        )
    }
}
