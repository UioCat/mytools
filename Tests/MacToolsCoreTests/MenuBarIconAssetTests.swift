import AppKit
import Foundation
import XCTest

final class MenuBarIconAssetTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testColorMenuBarAssetIsAnEightyEightPixelTransparentPNG() throws {
        let assetURL = repositoryRoot.appendingPathComponent(
            "Sources/MacTools/Resources/MenuBarIcon.png"
        )
        let exists = FileManager.default.fileExists(atPath: assetURL.path)

        XCTAssertTrue(exists, "Expected the source-controlled color menu bar icon")
        guard exists else { return }

        let data = try Data(contentsOf: assetURL)
        XCTAssertGreaterThanOrEqual(data.count, 24)
        XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])

        func dimension(at offset: Int) -> Int {
            data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
        }
        XCTAssertEqual(dimension(at: 16), 88)
        XCTAssertEqual(dimension(at: 20), 88)

        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertTrue(bitmap.hasAlpha)
        for point in [(0, 0), (87, 0), (0, 87), (87, 87)] {
            let color = try XCTUnwrap(bitmap.colorAt(x: point.0, y: point.1))
            XCTAssertLessThan(color.alphaComponent, 0.05)
        }
    }

    func testRuntimeMenuBarImageLoadsBundledColorAssetWithoutTemplateTinting() throws {
        let sourceURL = repositoryRoot.appendingPathComponent(
            "Sources/MacTools/App/MenuBarLogoImage.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Bundle.main.url(forResource: \"MenuBarIcon\""))
        XCTAssertTrue(source.contains("Bundle.module.url(forResource: \"MenuBarIcon\""))
        XCTAssertTrue(source.contains("NSImage(contentsOf: iconURL)"))
        XCTAssertTrue(source.contains("NSSize(width: 18, height: 18)"))
        XCTAssertTrue(source.contains("image.isTemplate = false"))
        XCTAssertFalse(source.contains("makeRibbonPaths"))
    }

    func testColorMenuBarAssetIsDeclaredAndCopiedIntoPackagedApp() throws {
        let packageSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let packagingScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/package_app.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(packageSource.contains("resources: [.process(\"Resources\")]"))
        XCTAssertTrue(
            packagingScript.contains("Sources/MacTools/Resources/MenuBarIcon.png")
        )
    }

    func testApplicationIconIsASourceControlledHighResolutionIconFamily() throws {
        let assetURL = repositoryRoot.appendingPathComponent(
            "Sources/MacTools/Resources/AppIcon.icns"
        )
        let exists = FileManager.default.fileExists(atPath: assetURL.path)

        XCTAssertTrue(exists, "Expected the source-controlled application icon")
        guard exists else { return }

        let image = try XCTUnwrap(NSImage(contentsOf: assetURL))
        let largestPixelDimension = image.representations
            .map { max($0.pixelsWide, $0.pixelsHigh) }
            .max()

        XCTAssertGreaterThanOrEqual(largestPixelDimension ?? 0, 512)
    }
}
