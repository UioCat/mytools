import Foundation
import XCTest

final class ReleaseWorkflowSourceTests: XCTestCase {
    func testReleaseWorkflowGeneratesSignedAppcastFromIsolatedInput() throws {
        let workflow = try sourceFile(".github/workflows/release.yml")

        XCTAssertTrue(workflow.contains("SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}"))
        XCTAssertTrue(workflow.contains("APPCAST_INPUT_DIR"))
        XCTAssertTrue(workflow.contains("generate_appcast"))
        XCTAssertTrue(workflow.contains("--ed-key-file -"))
        XCTAssertTrue(workflow.contains("BUILD_NUMBER=\"$(scripts/macos_build_number.sh \"$VERSION\")\""))
        XCTAssertTrue(
            workflow.contains(
                "printf 'MACOS_BUILD_NUMBER=%s\\n' \"$BUILD_NUMBER\" >> \"$GITHUB_ENV\""
            )
        )
        XCTAssertTrue(workflow.contains("--versions \"$MACOS_BUILD_NUMBER\""))
        XCTAssertFalse(workflow.contains("--versions \"$GITHUB_RUN_NUMBER\""))
        XCTAssertTrue(workflow.contains("'Print :CFBundleVersion'"))
        XCTAssertTrue(workflow.contains("= \"$MACOS_BUILD_NUMBER\""))
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

    func testReleaseWorkflowUsesStableAnonymousSigningAndAlwaysCleansUp() throws {
        let workflow = try sourceFile(".github/workflows/release.yml")

        XCTAssertTrue(workflow.contains("SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}"))
        XCTAssertTrue(workflow.contains("scripts/ci/import_anonymous_signing_identity.sh"))
        XCTAssertTrue(workflow.contains("MACOS_SIGNING_MODE: stable"))
        XCTAssertTrue(workflow.contains("MacTools Release Signing"))
        XCTAssertTrue(workflow.contains("25a3263958804c6d9429eb51b97ba2b16ca1fb67"))
        XCTAssertTrue(workflow.contains("Signature=adhoc"))
        XCTAssertTrue(workflow.contains("if: always()"))
        XCTAssertTrue(workflow.contains("scripts/ci/cleanup_anonymous_signing_identity.sh"))
        let buildStep = try XCTUnwrap(workflow.range(of: "- name: Build stable signed app"))
        let earlyCleanupStep = try XCTUnwrap(
            workflow.range(of: "- name: Retire anonymous signing identity after build")
        )
        let verificationStep = try XCTUnwrap(workflow.range(of: "- name: Verify app bundle"))
        XCTAssertLessThan(buildStep.lowerBound, earlyCleanupStep.lowerBound)
        XCTAssertLessThan(earlyCleanupStep.lowerBound, verificationStep.lowerBound)
        XCTAssertTrue(
            workflow.contains(
                "actions/checkout@11d5960a326750d5838078e36cf38b85af677262"
            )
        )
        XCTAssertTrue(workflow.contains("persist-credentials: false"))
        XCTAssertFalse(workflow.contains("MACOS_SIGNING_CERTIFICATE_P12"))
        XCTAssertFalse(workflow.contains("MACOS_SIGNING_CERTIFICATE_PASSWORD"))
        XCTAssertFalse(workflow.contains("MACOS_FORCE_ADHOC_SIGNING"))
        XCTAssertFalse(workflow.contains("Build ad-hoc signed app"))
    }

    func testSigningPreflightCannotPublishRelease() throws {
        let workflow = try sourceFile(".github/workflows/signing-preflight.yml")

        XCTAssertTrue(workflow.contains("push:"))
        XCTAssertTrue(workflow.contains("codex/anonymous-signing-preflight"))
        XCTAssertTrue(workflow.contains("github.actor == github.repository_owner"))
        XCTAssertTrue(workflow.contains("contents: read"))
        XCTAssertTrue(workflow.contains("scripts/ci/import_anonymous_signing_identity.sh"))
        XCTAssertTrue(workflow.contains("SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}"))
        XCTAssertTrue(workflow.contains("MACOS_SIGNING_MODE: stable"))
        XCTAssertTrue(workflow.contains("scripts/ci/cleanup_anonymous_signing_identity.sh"))
        let buildStep = try XCTUnwrap(workflow.range(of: "- name: Build stable signed app"))
        let earlyCleanupStep = try XCTUnwrap(
            workflow.range(of: "- name: Retire anonymous signing identity after build")
        )
        let verificationStep = try XCTUnwrap(
            workflow.range(of: "- name: Verify stable signed app without signing trust")
        )
        XCTAssertLessThan(buildStep.lowerBound, earlyCleanupStep.lowerBound)
        XCTAssertLessThan(earlyCleanupStep.lowerBound, verificationStep.lowerBound)
        XCTAssertFalse(workflow.contains("workflow_dispatch"))
        XCTAssertFalse(workflow.contains("gh release"))
        XCTAssertFalse(workflow.contains("contents: write"))
    }

    func testSigningImportReusesUserTrustOrAddsTemporarySystemTrust() throws {
        let importScript = try sourceFile("scripts/ci/import_anonymous_signing_identity.sh")
        let cleanupScript = try sourceFile("scripts/ci/cleanup_anonymous_signing_identity.sh")

        XCTAssertTrue(importScript.contains("MacToolsReleaseSigning.pem"))
        XCTAssertTrue(importScript.contains("derive_anonymous_signing_private_key.sh"))
        XCTAssertTrue(importScript.contains("SPARKLE_PRIVATE_KEY"))
        XCTAssertTrue(importScript.contains("25A3263958804C6D9429EB51B97BA2B16CA1FB67"))
        XCTAssertTrue(
            importScript.contains(
                "D098182A8CFA254D9834F5E0E7911C39418080D38B1AC921E8F90E90DDE3E157"
            )
        )
        XCTAssertTrue(
            importScript.contains(
                "D5B6541A61CE08813F5FA2C36862B40AC0CD992F8D6352FDFB1EDF23231FACFE"
            )
        )
        XCTAssertTrue(importScript.contains("unset SPARKLE_PRIVATE_KEY"))
        XCTAssertTrue(importScript.contains("openssl pkcs12"))
        XCTAssertTrue(importScript.contains("-legacy"))
        XCTAssertTrue(importScript.contains("sudo security add-trusted-cert"))
        XCTAssertTrue(importScript.contains("security verify-cert -p codeSign"))
        XCTAssertTrue(importScript.contains("SYSTEM_TRUST_OWNERSHIP_MARKER"))
        XCTAssertTrue(importScript.contains("manage_keychain_search_list.sh"))
        XCTAssertTrue(importScript.contains("unable to record ownership before adding temporary system trust"))
        XCTAssertTrue(
            importScript.contains(
                "already exists in the system keychain without valid code-signing trust"
            )
        )
        let markerWrite = try XCTUnwrap(
            importScript.range(of: ": > \"$SYSTEM_TRUST_OWNERSHIP_MARKER\"")
        )
        let trustMutation = try XCTUnwrap(
            importScript.range(of: "sudo security add-trusted-cert")
        )
        XCTAssertLessThan(markerWrite.lowerBound, trustMutation.lowerBound)
        XCTAssertTrue(importScript.contains("-p codeSign"))
        XCTAssertTrue(importScript.contains("security find-identity -v -p codesigning"))
        let identityValidation = try XCTUnwrap(
            importScript.range(of: "security find-identity -v -p codesigning")
        )
        let sensitiveMaterialRemoval = try XCTUnwrap(
            importScript.range(
                of: "for SENSITIVE_FILE in \"$SIGNING_PRIVATE_KEY\" \"$SIGNING_P12\""
            )
        )
        let workflowEnvironmentExport = try XCTUnwrap(
            importScript.range(of: "printf 'MACOS_CODESIGN_KEYCHAIN=%s")
        )
        XCTAssertLessThan(identityValidation.lowerBound, sensitiveMaterialRemoval.lowerBound)
        XCTAssertLessThan(sensitiveMaterialRemoval.lowerBound, workflowEnvironmentExport.lowerBound)
        XCTAssertFalse(importScript.contains("MACTOOLS_CI_SIGNING_PRIVATE_KEY="))
        XCTAssertFalse(importScript.contains("MACTOOLS_CI_SIGNING_P12="))
        XCTAssertFalse(importScript.contains("MACOS_SIGNING_CERTIFICATE_P12"))
        XCTAssertFalse(importScript.contains("MACOS_SIGNING_CERTIFICATE_PASSWORD"))
        XCTAssertTrue(cleanupScript.contains("sudo security remove-trusted-cert"))
        XCTAssertTrue(cleanupScript.contains("SYSTEM_TRUST_OWNERSHIP_MARKER"))
        XCTAssertFalse(cleanupScript.contains("ADDED_SYSTEM_TRUST:-unknown"))
        XCTAssertTrue(cleanupScript.contains("unable to verify system keychain cleanup"))
        XCTAssertTrue(cleanupScript.contains("unable to remove temporary system trust settings"))
        XCTAssertTrue(cleanupScript.contains("TRUST_SETTINGS_REMOVAL_SUCCEEDED"))
        XCTAssertTrue(
            cleanupScript.contains(
                "anonymous signing certificate remains trusted for code signing"
            )
        )
        XCTAssertTrue(cleanupScript.contains("security delete-keychain"))
        XCTAssertTrue(cleanupScript.contains("manage_keychain_search_list.sh"))
        XCTAssertTrue(cleanupScript.contains("SIGNING_PRIVATE_KEY"))
    }

    func testSigningCleanupPreservesPreexistingSystemTrustAfterEarlyImportFailure() throws {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MacToolsSigningCleanupTests-\(UUID().uuidString)")
        try fileManager.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: false
        )
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let securityTool = temporaryDirectory.appendingPathComponent("security")
        let sudoTool = temporaryDirectory.appendingPathComponent("sudo")
        let sudoLog = temporaryDirectory.appendingPathComponent("sudo.log")
        try """
        #!/bin/sh
        if [ "$1" = "find-certificate" ]; then
          printf '%s\n' 'SHA-1 hash: 25A3263958804C6D9429EB51B97BA2B16CA1FB67'
        fi
        exit 0
        """.write(to: securityTool, atomically: true, encoding: .utf8)
        try """
        #!/bin/sh
        printf '%s\n' "$*" >> "$MACTOOLS_TEST_SUDO_LOG"
        exit 0
        """.write(to: sudoTool, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: securityTool.path
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: sudoTool.path
        )

        let cleanup = Process()
        cleanup.executableURL = URL(fileURLWithPath: "/bin/bash")
        cleanup.arguments = [
            try repositoryRoot()
                .appendingPathComponent("scripts/ci/cleanup_anonymous_signing_identity.sh")
                .path,
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(temporaryDirectory.path):\(environment["PATH"] ?? "/usr/bin:/bin")"
        environment["RUNNER_TEMP"] = temporaryDirectory.path
        environment["MACTOOLS_CI_SIGNING_DIRECTORY"] = temporaryDirectory
            .appendingPathComponent("import-failed-before-trust-check")
            .path
        environment["MACTOOLS_TEST_SUDO_LOG"] = sudoLog.path
        cleanup.environment = environment
        try cleanup.run()
        cleanup.waitUntilExit()

        XCTAssertEqual(cleanup.terminationStatus, 0)
        XCTAssertFalse(
            fileManager.fileExists(atPath: sudoLog.path),
            "cleanup must not remove trust unless this task persisted its ownership marker"
        )
    }

    func testKeychainSearchListReadFailureCannotOverwriteOriginalList() throws {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MacToolsKeychainSearchListTests-\(UUID().uuidString)")
        try fileManager.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: false
        )
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let securityLog = temporaryDirectory.appendingPathComponent("security.log")
        let securityTool = temporaryDirectory.appendingPathComponent("security")
        try """
        #!/bin/sh
        printf '%s\n' "$*" >> "\(securityLog.path)"
        if [ "$1" = "list-keychains" ] && [ "$2" = "-d" ] && [ "$3" = "user" ]; then
          exit 42
        fi
        exit 0
        """.write(to: securityTool, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: securityTool.path
        )

        let stateFile = temporaryDirectory.appendingPathComponent("original-list")
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/bash")
        helper.arguments = [
            try repositoryRoot()
                .appendingPathComponent("scripts/ci/manage_keychain_search_list.sh")
                .path,
            "prepend",
            stateFile.path,
            temporaryDirectory.appendingPathComponent("signing.keychain-db").path,
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(temporaryDirectory.path):\(environment["PATH"] ?? "/usr/bin:/bin")"
        helper.environment = environment
        try helper.run()
        helper.waitUntilExit()

        XCTAssertNotEqual(helper.terminationStatus, 0)
        let calls = try String(contentsOf: securityLog, encoding: .utf8)
        XCTAssertEqual(calls.trimmingCharacters(in: .whitespacesAndNewlines), "list-keychains -d user")
        XCTAssertFalse(calls.contains(" -s "))
        XCTAssertFalse(fileManager.fileExists(atPath: stateFile.path))
    }

    func testSigningCleanupRemovesTrustWhenOwnershipMarkerExists() throws {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MacToolsSigningCleanupOwnedTests-\(UUID().uuidString)")
        let signingDirectory = temporaryDirectory.appendingPathComponent("signing")
        try fileManager.createDirectory(
            at: signingDirectory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let marker = signingDirectory.appendingPathComponent("system-trust-owned")
        try Data().write(to: marker)
        let sudoLog = temporaryDirectory.appendingPathComponent("sudo.log")
        try installFakeSecurityTools(
            in: temporaryDirectory,
            sudoLog: sudoLog,
            certificateQueryExitStatus: 0,
            verifyExitStatus: 1,
            removeTrustExitStatus: 0,
            deleteCertificateExitStatus: 0
        )

        let cleanup = try runSigningCleanup(
            temporaryDirectory: temporaryDirectory,
            signingDirectory: signingDirectory,
            sudoLog: sudoLog
        )

        XCTAssertEqual(cleanup.terminationStatus, 0)
        let commands = try String(contentsOf: sudoLog, encoding: .utf8)
        XCTAssertTrue(commands.contains("security remove-trusted-cert -d"))
        XCTAssertTrue(
            commands.contains(
                "security delete-certificate -Z 25A3263958804C6D9429EB51B97BA2B16CA1FB67"
            )
        )
        XCTAssertFalse(fileManager.fileExists(atPath: marker.path))
    }

    func testSigningCleanupKeepsOwnershipMarkerWhenSystemKeychainVerificationFails() throws {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MacToolsSigningCleanupFailureTests-\(UUID().uuidString)")
        let signingDirectory = temporaryDirectory.appendingPathComponent("signing")
        try fileManager.createDirectory(
            at: signingDirectory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let marker = signingDirectory.appendingPathComponent("system-trust-owned")
        try Data().write(to: marker)
        let sudoLog = temporaryDirectory.appendingPathComponent("sudo.log")
        try installFakeSecurityTools(
            in: temporaryDirectory,
            sudoLog: sudoLog,
            certificateQueryExitStatus: 42,
            verifyExitStatus: 0,
            removeTrustExitStatus: 1,
            deleteCertificateExitStatus: 1
        )

        let cleanup = try runSigningCleanup(
            temporaryDirectory: temporaryDirectory,
            signingDirectory: signingDirectory,
            sudoLog: sudoLog
        )

        XCTAssertNotEqual(cleanup.terminationStatus, 0)
        XCTAssertTrue(fileManager.fileExists(atPath: marker.path))
        XCTAssertTrue(fileManager.fileExists(atPath: sudoLog.path))
    }

    func testSigningCleanupKeepsOwnershipWhenTrustRemovalFailsButCertificateDeletionSucceeds() throws {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MacToolsSigningCleanupTrustFailureTests-\(UUID().uuidString)")
        let signingDirectory = temporaryDirectory.appendingPathComponent("signing")
        try fileManager.createDirectory(
            at: signingDirectory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let marker = signingDirectory.appendingPathComponent("system-trust-owned")
        try Data().write(to: marker)
        let sudoLog = temporaryDirectory.appendingPathComponent("sudo.log")
        try installFakeSecurityTools(
            in: temporaryDirectory,
            sudoLog: sudoLog,
            certificateQueryExitStatus: 0,
            verifyExitStatus: 0,
            removeTrustExitStatus: 1,
            deleteCertificateExitStatus: 0
        )

        let cleanup = try runSigningCleanup(
            temporaryDirectory: temporaryDirectory,
            signingDirectory: signingDirectory,
            sudoLog: sudoLog
        )

        XCTAssertNotEqual(cleanup.terminationStatus, 0)
        XCTAssertTrue(fileManager.fileExists(atPath: marker.path))
        let commands = try String(contentsOf: sudoLog, encoding: .utf8)
        XCTAssertTrue(commands.contains("security remove-trusted-cert -d"))
        XCTAssertTrue(commands.contains("security delete-certificate -Z"))
    }

    func testSigningCleanupKeepsOwnershipWhenTrustRemovalAndTrustVerificationBothFail() throws {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MacToolsSigningCleanupIndeterminateTrustTests-\(UUID().uuidString)")
        let signingDirectory = temporaryDirectory.appendingPathComponent("signing")
        try fileManager.createDirectory(
            at: signingDirectory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let marker = signingDirectory.appendingPathComponent("system-trust-owned")
        try Data().write(to: marker)
        let sudoLog = temporaryDirectory.appendingPathComponent("sudo.log")
        try installFakeSecurityTools(
            in: temporaryDirectory,
            sudoLog: sudoLog,
            certificateQueryExitStatus: 0,
            verifyExitStatus: 1,
            removeTrustExitStatus: 1,
            deleteCertificateExitStatus: 0
        )

        let cleanup = try runSigningCleanup(
            temporaryDirectory: temporaryDirectory,
            signingDirectory: signingDirectory,
            sudoLog: sudoLog
        )

        XCTAssertNotEqual(cleanup.terminationStatus, 0)
        XCTAssertTrue(fileManager.fileExists(atPath: marker.path))
    }

    private func installFakeSecurityTools(
        in directory: URL,
        sudoLog: URL,
        certificateQueryExitStatus: Int,
        verifyExitStatus: Int,
        removeTrustExitStatus: Int,
        deleteCertificateExitStatus: Int
    ) throws {
        let fileManager = FileManager.default
        let securityTool = directory.appendingPathComponent("security")
        let sudoTool = directory.appendingPathComponent("sudo")
        try """
        #!/bin/sh
        if [ "$1" = "find-certificate" ]; then
          exit \(certificateQueryExitStatus)
        fi
        if [ "$1" = "verify-cert" ]; then
          exit \(verifyExitStatus)
        fi
        exit 0
        """.write(to: securityTool, atomically: true, encoding: .utf8)
        try """
        #!/bin/sh
        printf '%s\n' "$*" >> "\(sudoLog.path)"
        if [ "$2" = "remove-trusted-cert" ]; then
          exit \(removeTrustExitStatus)
        fi
        if [ "$2" = "delete-certificate" ]; then
          exit \(deleteCertificateExitStatus)
        fi
        exit 0
        """.write(to: sudoTool, atomically: true, encoding: .utf8)
        for tool in [securityTool, sudoTool] {
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: tool.path
            )
        }
    }

    private func runSigningCleanup(
        temporaryDirectory: URL,
        signingDirectory: URL,
        sudoLog: URL
    ) throws -> Process {
        let cleanup = Process()
        cleanup.executableURL = URL(fileURLWithPath: "/bin/bash")
        cleanup.arguments = [
            try repositoryRoot()
                .appendingPathComponent("scripts/ci/cleanup_anonymous_signing_identity.sh")
                .path,
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(temporaryDirectory.path):\(environment["PATH"] ?? "/usr/bin:/bin")"
        environment["RUNNER_TEMP"] = temporaryDirectory.path
        environment["MACTOOLS_CI_SIGNING_DIRECTORY"] = signingDirectory.path
        environment["MACTOOLS_TEST_SUDO_LOG"] = sudoLog.path
        cleanup.environment = environment
        try cleanup.run()
        cleanup.waitUntilExit()
        return cleanup
    }

    private func sourceFile(_ path: String) throws -> String {
        return try String(
            contentsOf: try repositoryRoot().appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private func repositoryRoot() throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
