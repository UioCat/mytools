# Mac Tools MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Mac-only MVP as a native menu bar productivity app with a launcher panel, clipboard history, super right click, settings, permissions, and a translation SPI.

**Architecture:** Use a single-process macOS app for the MVP, with AppKit owning lifecycle/system integration and SwiftUI owning panels/settings. Keep behavior behind focused services so clipboard, hotkeys, permissions, right-click handling, translation, and storage can be tested independently.

**Tech Stack:** Swift 5.10+, Swift Package Manager, AppKit, SwiftUI, Combine, Carbon global hotkeys, CGEvent event taps, NSPasteboard, GRDB(SQLite), XCTest.

---

## Scope Check

The approved spec spans several subsystems: app shell, hotkeys, clipboard history, local storage, paste actions, permissions, super right click, file actions, and translation SPI. This plan keeps them in one MVP roadmap but splits them into independently testable tasks. If delivery time becomes tight, ship through Task 8 first for a working clipboard launcher, then add super right click in Tasks 10-12.

Implementation requires an accepted Xcode/Apple SDK license before `swift build` or `swift test` can run. If the machine reports the license error, run this manually in Terminal before execution:

```bash
sudo xcodebuild -license
```

## File Structure

Create a SwiftPM workspace instead of hand-authoring an Xcode project first. The executable runs as a menu bar app through AppKit, and the core library stays testable through `swift test`.

```text
/Users/bytedance/Documents/mytools/
  Package.swift
  Sources/
    MacTools/
      main.swift
      App/
        AppDelegate.swift
        AppEnvironment.swift
        MenuBarController.swift
    MacToolsCore/
      Clipboard/
        ClipboardClassifier.swift
        ClipboardItem.swift
        ClipboardPayload.swift
        ClipboardService.swift
        PasteboardClient.swift
      Storage/
        ClipboardDatabase.swift
        ClipboardRepository.swift
        FileCache.swift
      HotKeys/
        HotKey.swift
        HotKeyService.swift
      Panels/
        MainPanelController.swift
      Paste/
        PasteActionService.swift
      Permissions/
        PermissionService.swift
      RightClick/
        RightClickEvent.swift
        RightClickStateMachine.swift
        SelectionCaptureService.swift
        SuperRightClickService.swift
      Settings/
        AppSettings.swift
        SettingsStore.swift
      Translation/
        BaiduTranslationProvider.swift
        TranslationProvider.swift
        TranslationService.swift
      FileActions/
        FileActionService.swift
      UI/
        MainPanelView.swift
        ClipboardListView.swift
        ClipboardRowView.swift
        SettingsView.swift
        ContextActionView.swift
      Utilities/
        Clock.swift
        Logger.swift
  Tests/
    MacToolsCoreTests/
      ClipboardClassifierTests.swift
      ClipboardRepositoryTests.swift
      FileCacheTests.swift
      ClipboardServiceTests.swift
      HotKeyServiceTests.swift
      PasteActionServiceTests.swift
      PermissionServiceTests.swift
      RightClickStateMachineTests.swift
      TranslationServiceTests.swift
      FileActionServiceTests.swift
  scripts/
    package_app.sh
  docs/
    architecture/mac-tools-architecture.html
    superpowers/specs/2026-06-03-mac-tools-design.md
    superpowers/plans/2026-06-03-mac-tools-implementation.md
```

## Task 1: SwiftPM Scaffold And App Shell

**Files:**
- Create: `/Users/bytedance/Documents/mytools/Package.swift`
- Create: `/Users/bytedance/Documents/mytools/Sources/MacTools/main.swift`
- Create: `/Users/bytedance/Documents/mytools/Sources/MacTools/App/AppDelegate.swift`
- Create: `/Users/bytedance/Documents/mytools/Sources/MacTools/App/MenuBarController.swift`
- Create: `/Users/bytedance/Documents/mytools/Sources/MacTools/App/AppEnvironment.swift`
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/Utilities/Logger.swift`
- Test: `/Users/bytedance/Documents/mytools/Tests/MacToolsCoreTests/ScaffoldTests.swift`

- [ ] **Step 1: Write the scaffold test**

```swift
import XCTest
@testable import MacToolsCore

final class ScaffoldTests: XCTestCase {
    func testLoggerCanRecordMessages() {
        let logger = Logger()
        logger.info("boot")
        XCTAssertEqual(logger.messages, ["INFO boot"])
    }
}
```

- [ ] **Step 2: Create `Package.swift`**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MacTools",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacTools", targets: ["MacTools"]),
        .library(name: "MacToolsCore", targets: ["MacToolsCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .executableTarget(
            name: "MacTools",
            dependencies: ["MacToolsCore"]
        ),
        .target(
            name: "MacToolsCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "MacToolsCoreTests",
            dependencies: ["MacToolsCore"]
        )
    ]
)
```

- [ ] **Step 3: Create the logger**

```swift
public final class Logger {
    public private(set) var messages: [String] = []

    public init() {}

    public func info(_ message: String) {
        messages.append("INFO \(message)")
    }

    public func error(_ message: String) {
        messages.append("ERROR \(message)")
    }
}
```

- [ ] **Step 4: Create the AppKit entry point**

```swift
import AppKit
import MacToolsCore

@main
final class MacToolsMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
```

- [ ] **Step 5: Create lifecycle shell**

```swift
import AppKit
import MacToolsCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let environment = AppEnvironment()
    private lazy var menuBarController = MenuBarController(environment: environment)

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController.install()
        environment.logger.info("application did finish launching")
    }
}
```

```swift
import Foundation
import MacToolsCore

final class AppEnvironment {
    let logger = Logger()
}
```

```swift
import AppKit

final class MenuBarController {
    private let environment: AppEnvironment
    private var statusItem: NSStatusItem?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "MT"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open", action: #selector(open), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func open() {
        environment.logger.info("menu open selected")
    }
}
```

- [ ] **Step 6: Run scaffold tests**

Run:

```bash
swift test --filter ScaffoldTests
```

Expected: `ScaffoldTests` passes.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "chore: scaffold mac tools app"
```

## Task 2: Settings Model And Persistence

**Files:**
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/Settings/AppSettings.swift`
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/Settings/SettingsStore.swift`
- Test: `/Users/bytedance/Documents/mytools/Tests/MacToolsCoreTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write settings tests**

```swift
import XCTest
@testable import MacToolsCore

final class SettingsStoreTests: XCTestCase {
    func testDefaultsMatchApprovedShortcuts() {
        let settings = AppSettings.defaults
        XCTAssertEqual(settings.mainPanelShortcut.displayValue, "Option+Space")
        XCTAssertEqual(settings.clipboardShortcut.displayValue, "Option+1")
        XCTAssertEqual(settings.superRightClick.longPressMilliseconds, 600)
        XCTAssertTrue(settings.clipboard.isRecordingEnabled)
    }

    func testSettingsRoundTripToDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("settings.json")
        let store = SettingsStore(fileURL: url)
        var settings = AppSettings.defaults
        settings.clipboard.maxHistoryCount = 250

        try store.save(settings)
        let loaded = try store.load()

        XCTAssertEqual(loaded.clipboard.maxHistoryCount, 250)
        XCTAssertEqual(loaded.mainPanelShortcut.displayValue, "Option+Space")
    }
}
```

- [ ] **Step 2: Implement settings types**

```swift
import Foundation

public struct HotKeyBinding: Codable, Equatable {
    public var key: String
    public var modifiers: [String]

    public var displayValue: String {
        (modifiers + [key]).joined(separator: "+")
    }
}

public struct ClipboardSettings: Codable, Equatable {
    public var isRecordingEnabled: Bool
    public var maxHistoryCount: Int
    public var maxCacheMegabytes: Int
}

public struct SuperRightClickSettings: Codable, Equatable {
    public var isEnabled: Bool
    public var longPressMilliseconds: Int
}

public struct TranslationSettings: Codable, Equatable {
    public var providerID: String
}

public struct AppSettings: Codable, Equatable {
    public var mainPanelShortcut: HotKeyBinding
    public var clipboardShortcut: HotKeyBinding
    public var reservedTool2Shortcut: HotKeyBinding
    public var reservedTool3Shortcut: HotKeyBinding
    public var clipboard: ClipboardSettings
    public var superRightClick: SuperRightClickSettings
    public var translation: TranslationSettings

    public static let defaults = AppSettings(
        mainPanelShortcut: HotKeyBinding(key: "Space", modifiers: ["Option"]),
        clipboardShortcut: HotKeyBinding(key: "1", modifiers: ["Option"]),
        reservedTool2Shortcut: HotKeyBinding(key: "2", modifiers: ["Option"]),
        reservedTool3Shortcut: HotKeyBinding(key: "3", modifiers: ["Option"]),
        clipboard: ClipboardSettings(
            isRecordingEnabled: true,
            maxHistoryCount: 500,
            maxCacheMegabytes: 1024
        ),
        superRightClick: SuperRightClickSettings(
            isEnabled: true,
            longPressMilliseconds: 600
        ),
        translation: TranslationSettings(providerID: "baidu")
    )
}
```

- [ ] **Step 3: Implement settings store**

```swift
import Foundation

public final class SettingsStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .defaults
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(AppSettings.self, from: data)
    }

    public func save(_ settings: AppSettings) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: [.atomic])
    }
}
```

- [ ] **Step 4: Run settings tests**

Run:

```bash
swift test --filter SettingsStoreTests
```

Expected: all settings tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacToolsCore/Settings Tests/MacToolsCoreTests/SettingsStoreTests.swift
git commit -m "feat: add settings persistence"
```

## Task 3: Clipboard Domain And Classification

**Files:**
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/Clipboard/ClipboardItem.swift`
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/Clipboard/ClipboardPayload.swift`
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/Clipboard/ClipboardClassifier.swift`
- Test: `/Users/bytedance/Documents/mytools/Tests/MacToolsCoreTests/ClipboardClassifierTests.swift`

- [ ] **Step 1: Write classifier tests**

```swift
import XCTest
@testable import MacToolsCore

final class ClipboardClassifierTests: XCTestCase {
    func testClassifiesPlainText() {
        let payload = ClipboardPayload(text: "hello world")
        let item = ClipboardClassifier().classify(payload: payload, sourceApp: "Notes")
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.displayTitle, "hello world")
        XCTAssertEqual(item.sourceApp, "Notes")
    }

    func testClassifiesFolderPath() {
        let url = URL(fileURLWithPath: "/Users/bytedance/Documents")
        let payload = ClipboardPayload(fileURLs: [url])
        let item = ClipboardClassifier().classify(payload: payload, sourceApp: "Finder")
        XCTAssertEqual(item.kind, .folder)
        XCTAssertEqual(item.originalPath, "/Users/bytedance/Documents")
        XCTAssertEqual(item.displayTitle, "Documents")
    }

    func testClassifiesRawImageData() {
        let payload = ClipboardPayload(imageData: Data([0x89, 0x50, 0x4E, 0x47]))
        let item = ClipboardClassifier().classify(payload: payload, sourceApp: "Preview")
        XCTAssertEqual(item.kind, .imageData)
        XCTAssertEqual(item.displayTitle, "Image from Preview")
    }
}
```

- [ ] **Step 2: Implement clipboard models**

```swift
import Foundation

public enum ClipboardContentKind: String, Codable, Equatable, CaseIterable {
    case text
    case url
    case file
    case folder
    case imageFile
    case imageData
    case unknown
}

public struct ClipboardItem: Codable, Equatable, Identifiable {
    public var id: UUID
    public var kind: ClipboardContentKind
    public var displayTitle: String
    public var searchableText: String
    public var text: String?
    public var originalPath: String?
    public var cachedFilePath: String?
    public var thumbnailPath: String?
    public var sourceApp: String?
    public var createdAt: Date
    public var lastUsedAt: Date?
    public var useCount: Int
    public var isPinned: Bool
    public var isFavorite: Bool
}

public struct ClipboardPayload: Equatable {
    public var text: String?
    public var fileURLs: [URL]
    public var imageData: Data?

    public init(text: String? = nil, fileURLs: [URL] = [], imageData: Data? = nil) {
        self.text = text
        self.fileURLs = fileURLs
        self.imageData = imageData
    }
}
```

- [ ] **Step 3: Implement classifier**

```swift
import Foundation

public final class ClipboardClassifier {
    public init() {}

    public func classify(payload: ClipboardPayload, sourceApp: String?) -> ClipboardItem {
        let now = Date()

        if let firstURL = payload.fileURLs.first {
            let path = firstURL.path
            let isDirectory = (try? firstURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let isImage = ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(firstURL.pathExtension.lowercased())
            let kind: ClipboardContentKind = isDirectory ? .folder : (isImage ? .imageFile : .file)
            return makeItem(
                kind: kind,
                title: firstURL.lastPathComponent,
                searchableText: path,
                text: nil,
                originalPath: path,
                sourceApp: sourceApp,
                now: now
            )
        }

        if let imageData = payload.imageData, !imageData.isEmpty {
            return makeItem(
                kind: .imageData,
                title: "Image from \(sourceApp ?? "Clipboard")",
                searchableText: sourceApp ?? "image",
                text: nil,
                originalPath: nil,
                sourceApp: sourceApp,
                now: now
            )
        }

        if let text = payload.text, !text.isEmpty {
            let kind: ClipboardContentKind = URL(string: text)?.scheme == nil ? .text : .url
            return makeItem(
                kind: kind,
                title: String(text.prefix(80)),
                searchableText: text,
                text: text,
                originalPath: nil,
                sourceApp: sourceApp,
                now: now
            )
        }

        return makeItem(
            kind: .unknown,
            title: "Unknown clipboard item",
            searchableText: sourceApp ?? "",
            text: nil,
            originalPath: nil,
            sourceApp: sourceApp,
            now: now
        )
    }

    private func makeItem(
        kind: ClipboardContentKind,
        title: String,
        searchableText: String,
        text: String?,
        originalPath: String?,
        sourceApp: String?,
        now: Date
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: kind,
            displayTitle: title,
            searchableText: searchableText,
            text: text,
            originalPath: originalPath,
            cachedFilePath: nil,
            thumbnailPath: nil,
            sourceApp: sourceApp,
            createdAt: now,
            lastUsedAt: nil,
            useCount: 0,
            isPinned: false,
            isFavorite: false
        )
    }
}
```

- [ ] **Step 4: Run classifier tests**

Run:

```bash
swift test --filter ClipboardClassifierTests
```

Expected: all classifier tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacToolsCore/Clipboard Tests/MacToolsCoreTests/ClipboardClassifierTests.swift
git commit -m "feat: classify clipboard payloads"
```

## Task 4: SQLite Clipboard Repository

**Files:**
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/Storage/ClipboardDatabase.swift`
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/Storage/ClipboardRepository.swift`
- Test: `/Users/bytedance/Documents/mytools/Tests/MacToolsCoreTests/ClipboardRepositoryTests.swift`

- [ ] **Step 1: Write repository tests**

```swift
import XCTest
@testable import MacToolsCore

final class ClipboardRepositoryTests: XCTestCase {
    func testInsertAndSearchTextItem() throws {
        let db = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: db)
        let item = ClipboardItem(
            id: UUID(),
            kind: .text,
            displayTitle: "Swift notes",
            searchableText: "Swift AppKit clipboard",
            text: "Swift AppKit clipboard",
            originalPath: nil,
            cachedFilePath: nil,
            thumbnailPath: nil,
            sourceApp: "Notes",
            createdAt: Date(timeIntervalSince1970: 100),
            lastUsedAt: nil,
            useCount: 0,
            isPinned: false,
            isFavorite: true
        )

        try repository.upsert(item)
        let results = try repository.search("appkit", limit: 20)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].displayTitle, "Swift notes")
        XCTAssertTrue(results[0].isFavorite)
    }

    func testPinnedItemsSortBeforeNormalItems() throws {
        let db = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: db)
        try repository.upsert(.testItem(title: "normal", pinned: false, createdAt: 200))
        try repository.upsert(.testItem(title: "pinned", pinned: true, createdAt: 100))

        let results = try repository.search("", limit: 20)

        XCTAssertEqual(results.map(\.displayTitle), ["pinned", "normal"])
    }
}

private extension ClipboardItem {
    static func testItem(title: String, pinned: Bool, createdAt: TimeInterval) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .text,
            displayTitle: title,
            searchableText: title,
            text: title,
            originalPath: nil,
            cachedFilePath: nil,
            thumbnailPath: nil,
            sourceApp: nil,
            createdAt: Date(timeIntervalSince1970: createdAt),
            lastUsedAt: nil,
            useCount: 0,
            isPinned: pinned,
            isFavorite: false
        )
    }
}
```

- [ ] **Step 2: Implement database migrations**

```swift
import Foundation
import GRDB

public final class ClipboardDatabase {
    public let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    public static func inMemory() throws -> ClipboardDatabase {
        try ClipboardDatabase(writer: DatabaseQueue())
    }

    public static func at(_ url: URL) throws -> ClipboardDatabase {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return try ClipboardDatabase(writer: DatabaseQueue(path: url.path))
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createClipboardItems") { db in
            try db.create(table: "clipboard_items", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("kind", .text).notNull()
                table.column("displayTitle", .text).notNull()
                table.column("searchableText", .text).notNull()
                table.column("text", .text)
                table.column("originalPath", .text)
                table.column("cachedFilePath", .text)
                table.column("thumbnailPath", .text)
                table.column("sourceApp", .text)
                table.column("createdAt", .datetime).notNull()
                table.column("lastUsedAt", .datetime)
                table.column("useCount", .integer).notNull()
                table.column("isPinned", .boolean).notNull()
                table.column("isFavorite", .boolean).notNull()
            }
            try db.create(index: "idx_clipboard_search", on: "clipboard_items", columns: ["searchableText"])
            try db.create(index: "idx_clipboard_order", on: "clipboard_items", columns: ["isPinned", "createdAt"])
        }
        return migrator
    }
}
```

- [ ] **Step 3: Implement repository**

```swift
import Foundation
import GRDB

extension ClipboardItem: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "clipboard_items"
}

public final class ClipboardRepository {
    private let database: ClipboardDatabase

    public init(database: ClipboardDatabase) {
        self.database = database
    }

    public func upsert(_ item: ClipboardItem) throws {
        try database.writer.write { db in
            try item.save(db)
        }
    }

    public func search(_ query: String, limit: Int) throws -> [ClipboardItem] {
        try database.writer.read { db in
            let request: QueryInterfaceRequest<ClipboardItem>
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                request = ClipboardItem
                    .order(Column("isPinned").desc, Column("createdAt").desc)
                    .limit(limit)
            } else {
                request = ClipboardItem
                    .filter(Column("searchableText").like("%\(query)%") || Column("displayTitle").like("%\(query)%"))
                    .order(Column("isPinned").desc, Column("createdAt").desc)
                    .limit(limit)
            }
            return try request.fetchAll(db)
        }
    }

    public func markUsed(id: UUID, at date: Date) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                UPDATE clipboard_items
                SET lastUsedAt = ?, useCount = useCount + 1
                WHERE id = ?
                """,
                arguments: [date, id.uuidString]
            )
        }
    }
}
```

- [ ] **Step 4: Run repository tests**

Run:

```bash
swift test --filter ClipboardRepositoryTests
```

Expected: repository tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacToolsCore/Storage Tests/MacToolsCoreTests/ClipboardRepositoryTests.swift
git commit -m "feat: persist clipboard history"
```

## Task 5: File Cache For Images And Large Clipboard Data

**Files:**
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/Storage/FileCache.swift`
- Test: `/Users/bytedance/Documents/mytools/Tests/MacToolsCoreTests/FileCacheTests.swift`

- [ ] **Step 1: Write file cache tests**

```swift
import XCTest
@testable import MacToolsCore

final class FileCacheTests: XCTestCase {
    func testStoresImageDataWithStableExtension() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = FileCache(rootDirectory: root)
        let data = Data([1, 2, 3, 4])

        let result = try cache.store(data: data, preferredExtension: "png")

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.fileURL.path))
        XCTAssertEqual(result.fileURL.pathExtension, "png")
    }

    func testReportsStorageUsage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = FileCache(rootDirectory: root)
        _ = try cache.store(data: Data(repeating: 1, count: 12), preferredExtension: "png")

        XCTAssertEqual(try cache.totalBytes(), 12)
    }
}
```

- [ ] **Step 2: Implement file cache**

```swift
import Foundation

public struct CachedFile: Equatable {
    public let fileURL: URL
}

public final class FileCache {
    private let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func store(data: Data, preferredExtension: String) throws -> CachedFile {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let filename = UUID().uuidString + "." + preferredExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let url = rootDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic])
        return CachedFile(fileURL: url)
    }

    public func totalBytes() throws -> Int {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else {
            return 0
        }
        let urls = try FileManager.default.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: [.fileSizeKey])
        return try urls.reduce(0) { partial, url in
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            return partial + size
        }
    }

    public func removeAll() throws {
        if FileManager.default.fileExists(atPath: rootDirectory.path) {
            try FileManager.default.removeItem(at: rootDirectory)
        }
    }
}
```

- [ ] **Step 3: Run cache tests**

Run:

```bash
swift test --filter FileCacheTests
```

Expected: file cache tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/MacToolsCore/Storage/FileCache.swift Tests/MacToolsCoreTests/FileCacheTests.swift
git commit -m "feat: add clipboard file cache"
```

## Task 6: Pasteboard Client And Clipboard Recording Service

**Files:**
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/Clipboard/PasteboardClient.swift`
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/Clipboard/ClipboardService.swift`
- Test: `/Users/bytedance/Documents/mytools/Tests/MacToolsCoreTests/ClipboardServiceTests.swift`

- [ ] **Step 1: Write service tests with fake pasteboard**

```swift
import XCTest
@testable import MacToolsCore

final class ClipboardServiceTests: XCTestCase {
    func testRecordsNewPayloadWhenRecordingEnabled() throws {
        let db = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: db)
        let fake = FakePasteboardClient(payload: ClipboardPayload(text: "hello clipboard"), changeCount: 1)
        let service = ClipboardService(
            pasteboard: fake,
            classifier: ClipboardClassifier(),
            repository: repository,
            settings: .defaults
        )

        try service.pollOnce(sourceApp: "Tests")

        let results = try repository.search("hello", limit: 10)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].text, "hello clipboard")
    }

    func testDoesNotRecordWhenPaused() throws {
        let db = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: db)
        let fake = FakePasteboardClient(payload: ClipboardPayload(text: "secret"), changeCount: 1)
        var settings = AppSettings.defaults
        settings.clipboard.isRecordingEnabled = false
        let service = ClipboardService(
            pasteboard: fake,
            classifier: ClipboardClassifier(),
            repository: repository,
            settings: settings
        )

        try service.pollOnce(sourceApp: "Tests")

        XCTAssertTrue(try repository.search("", limit: 10).isEmpty)
    }
}

private struct FakePasteboardClient: PasteboardClient {
    let payload: ClipboardPayload
    let changeCount: Int

    func readPayload() -> ClipboardPayload {
        payload
    }
}
```

- [ ] **Step 2: Implement pasteboard protocol and AppKit client**

```swift
import AppKit
import Foundation

public protocol PasteboardClient {
    var changeCount: Int { get }
    func readPayload() -> ClipboardPayload
}

public final class SystemPasteboardClient: PasteboardClient {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int {
        pasteboard.changeCount
    }

    public func readPayload() -> ClipboardPayload {
        let text = pasteboard.string(forType: .string)
        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
        return ClipboardPayload(text: text, fileURLs: urls, imageData: imageData)
    }
}
```

- [ ] **Step 3: Implement clipboard service**

```swift
import Foundation

public final class ClipboardService {
    private let pasteboard: PasteboardClient
    private let classifier: ClipboardClassifier
    private let repository: ClipboardRepository
    private var settings: AppSettings
    private var lastChangeCount: Int

    public init(
        pasteboard: PasteboardClient,
        classifier: ClipboardClassifier,
        repository: ClipboardRepository,
        settings: AppSettings
    ) {
        self.pasteboard = pasteboard
        self.classifier = classifier
        self.repository = repository
        self.settings = settings
        self.lastChangeCount = pasteboard.changeCount
    }

    public func updateSettings(_ settings: AppSettings) {
        self.settings = settings
    }

    public func pollOnce(sourceApp: String?) throws {
        guard settings.clipboard.isRecordingEnabled else {
            lastChangeCount = pasteboard.changeCount
            return
        }
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }
        lastChangeCount = pasteboard.changeCount
        let payload = pasteboard.readPayload()
        let item = classifier.classify(payload: payload, sourceApp: sourceApp)
        guard item.kind != .unknown else {
            return
        }
        try repository.upsert(item)
    }
}
```

- [ ] **Step 4: Run clipboard service tests**

Run:

```bash
swift test --filter ClipboardServiceTests
```

Expected: service tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacToolsCore/Clipboard Tests/MacToolsCoreTests/ClipboardServiceTests.swift
git commit -m "feat: record clipboard changes"
```

## Task 7: Main Panel And Clipboard Search View

**Files:**
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/Panels/MainPanelController.swift`
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/UI/MainPanelView.swift`
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/UI/ClipboardListView.swift`
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/UI/ClipboardRowView.swift`
- Modify: `/Users/bytedance/Documents/mytools/Sources/MacTools/App/AppEnvironment.swift`
- Modify: `/Users/bytedance/Documents/mytools/Sources/MacTools/App/MenuBarController.swift`

- [ ] **Step 1: Create panel controller**

```swift
import AppKit
import SwiftUI

public final class MainPanelController {
    private var panel: NSPanel?
    private let rootView: AnyView

    public init<Content: View>(rootView: Content) {
        self.rootView = AnyView(rootView)
    }

    public func show() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.contentView = NSHostingView(rootView: rootView)
            self.panel = panel
        }
        panel?.center()
        panel?.orderFrontRegardless()
    }

    public func hide() {
        panel?.orderOut(nil)
    }
}
```

- [ ] **Step 2: Create SwiftUI panel views**

```swift
import SwiftUI

public struct MainPanelView: View {
    @State private var query = ""
    public let items: [ClipboardItem]
    public let onSelect: (ClipboardItem) -> Void

    public init(items: [ClipboardItem], onSelect: @escaping (ClipboardItem) -> Void) {
        self.items = items
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            TextField("Search tools and clipboard", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .medium))
                .padding(16)
            Divider()
            ClipboardListView(items: filteredItems, onSelect: onSelect)
        }
        .frame(width: 760, height: 520)
    }

    private var filteredItems: [ClipboardItem] {
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query) ||
            $0.searchableText.localizedCaseInsensitiveContains(query)
        }
    }
}
```

```swift
import SwiftUI

public struct ClipboardListView: View {
    public let items: [ClipboardItem]
    public let onSelect: (ClipboardItem) -> Void

    public init(items: [ClipboardItem], onSelect: @escaping (ClipboardItem) -> Void) {
        self.items = items
        self.onSelect = onSelect
    }

    public var body: some View {
        List(items) { item in
            Button {
                onSelect(item)
            } label: {
                ClipboardRowView(item: item)
            }
            .buttonStyle(.plain)
        }
    }
}
```

```swift
import SwiftUI

public struct ClipboardRowView: View {
    public let item: ClipboardItem

    public init(item: ClipboardItem) {
        self.item = item
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(icon)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(item.sourceApp ?? item.kind.rawValue)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if item.isPinned { Text("Pinned").font(.system(size: 10)) }
            if item.isFavorite { Text("Favorite").font(.system(size: 10)) }
        }
        .padding(.vertical, 6)
    }

    private var icon: String {
        switch item.kind {
        case .text: "T"
        case .url: "URL"
        case .file: "F"
        case .folder: "D"
        case .imageFile, .imageData: "IMG"
        case .unknown: "?"
        }
    }
}
```

- [ ] **Step 3: Wire menu open to panel**

Use a temporary empty item list until the view model lands:

```swift
import Foundation
import MacToolsCore

final class AppEnvironment {
    let logger = Logger()
    lazy var mainPanel = MainPanelController(
        rootView: MainPanelView(items: [], onSelect: { _ in })
    )
}
```

```swift
@objc private func open() {
    environment.mainPanel.show()
}
```

- [ ] **Step 4: Run app manually**

Run:

```bash
swift run MacTools
```

Expected: menu bar item appears as `MT`; choosing `Open` shows the main panel.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacTools Sources/MacToolsCore/Panels Sources/MacToolsCore/UI
git commit -m "feat: add main panel shell"
```

## Task 8: Global Hotkeys

**Files:**
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/HotKeys/HotKey.swift`
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/HotKeys/HotKeyService.swift`
- Test: `/Users/bytedance/Documents/mytools/Tests/MacToolsCoreTests/HotKeyServiceTests.swift`
- Modify: `/Users/bytedance/Documents/mytools/Sources/MacTools/App/AppDelegate.swift`

- [ ] **Step 1: Write hotkey mapping tests**

```swift
import XCTest
@testable import MacToolsCore

final class HotKeyServiceTests: XCTestCase {
    func testDefaultBindingsProduceToolIDs() {
        let service = HotKeyService(registrar: FakeHotKeyRegistrar())
        service.configure(settings: .defaults)

        XCTAssertEqual(service.binding(for: "Option+Space"), .mainPanel)
        XCTAssertEqual(service.binding(for: "Option+1"), .clipboard)
    }
}

private final class FakeHotKeyRegistrar: HotKeyRegistrar {
    func register(_ hotKey: HotKey, handler: @escaping () -> Void) throws {}
    func unregisterAll() {}
}
```

- [ ] **Step 2: Implement hotkey types and service boundary**

```swift
import Foundation

public enum HotKeyTarget: String, Equatable {
    case mainPanel
    case clipboard
    case reservedTool2
    case reservedTool3
}

public struct HotKey: Equatable, Hashable {
    public let displayValue: String
    public let key: String
    public let modifiers: [String]
}

public protocol HotKeyRegistrar {
    func register(_ hotKey: HotKey, handler: @escaping () -> Void) throws
    func unregisterAll()
}

public final class HotKeyService {
    private let registrar: HotKeyRegistrar
    private var bindings: [String: HotKeyTarget] = [:]

    public init(registrar: HotKeyRegistrar) {
        self.registrar = registrar
    }

    public func configure(settings: AppSettings) {
        registrar.unregisterAll()
        bindings = [
            settings.mainPanelShortcut.displayValue: .mainPanel,
            settings.clipboardShortcut.displayValue: .clipboard,
            settings.reservedTool2Shortcut.displayValue: .reservedTool2,
            settings.reservedTool3Shortcut.displayValue: .reservedTool3
        ]
    }

    public func binding(for displayValue: String) -> HotKeyTarget? {
        bindings[displayValue]
    }
}
```

- [ ] **Step 3: Add Carbon registrar**

Implement `CarbonHotKeyRegistrar` in `HotKeyService.swift` after tests pass. Use `RegisterEventHotKey`, store `EventHotKeyRef`, and map callbacks to handlers. Keep conversion from `HotKeyBinding` to Carbon key codes in a private method so it can be tested separately.

Key code mapping required for MVP:

```swift
private let keyCodes: [String: UInt32] = [
    "Space": 49,
    "1": 18,
    "2": 19,
    "3": 20
]
```

Modifier mapping:

```swift
private let optionModifier: UInt32 = UInt32(optionKey)
```

- [ ] **Step 4: Wire hotkeys at launch**

In `AppDelegate.applicationDidFinishLaunching`, load settings and register:

```swift
let settings = AppSettings.defaults
environment.hotKeyService.configure(settings: settings)
```

Map `.mainPanel` and `.clipboard` handlers to `environment.mainPanel.show()`.

- [ ] **Step 5: Manual hotkey verification**

Run:

```bash
swift run MacTools
```

Expected:
- `Option + Space` opens the main panel.
- `Option + 1` opens the same panel scoped to clipboard results for now.

- [ ] **Step 6: Commit**

```bash
git add Sources/MacToolsCore/HotKeys Sources/MacTools/App Tests/MacToolsCoreTests/HotKeyServiceTests.swift
git commit -m "feat: register global hotkeys"
```

## Task 9: Paste Action Service

**Files:**
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/Paste/PasteActionService.swift`
- Test: `/Users/bytedance/Documents/mytools/Tests/MacToolsCoreTests/PasteActionServiceTests.swift`

- [ ] **Step 1: Write paste action tests**

```swift
import XCTest
@testable import MacToolsCore

final class PasteActionServiceTests: XCTestCase {
    func testCopyOnlyWritesTextToPasteboard() throws {
        let pasteboard = FakeWritablePasteboard()
        let service = PasteActionService(pasteboard: pasteboard, eventSender: FakePasteEventSender())
        let item = ClipboardItem.testText("hello")

        try service.copy(item)

        XCTAssertEqual(pasteboard.writtenText, "hello")
    }

    func testCopyAndPasteSendsPasteEvent() throws {
        let pasteboard = FakeWritablePasteboard()
        let sender = FakePasteEventSender()
        let service = PasteActionService(pasteboard: pasteboard, eventSender: sender)

        try service.copyAndPaste(ClipboardItem.testText("hello"))

        XCTAssertTrue(sender.didSendPaste)
    }
}
```

- [ ] **Step 2: Implement paste service protocols**

```swift
import AppKit
import Foundation

public protocol WritablePasteboard {
    func writeText(_ text: String)
    func writeFileURL(_ url: URL)
}

public protocol PasteEventSender {
    func sendPasteShortcut()
}

public final class PasteActionService {
    private let pasteboard: WritablePasteboard
    private let eventSender: PasteEventSender

    public init(pasteboard: WritablePasteboard, eventSender: PasteEventSender) {
        self.pasteboard = pasteboard
        self.eventSender = eventSender
    }

    public func copy(_ item: ClipboardItem) throws {
        if let text = item.text {
            pasteboard.writeText(text)
            return
        }
        if let path = item.originalPath ?? item.cachedFilePath {
            pasteboard.writeFileURL(URL(fileURLWithPath: path))
            return
        }
        throw PasteActionError.unsupportedItem
    }

    public func copyAndPaste(_ item: ClipboardItem) throws {
        try copy(item)
        eventSender.sendPasteShortcut()
    }
}

public enum PasteActionError: Error, Equatable {
    case unsupportedItem
}
```

- [ ] **Step 3: Add system implementations**

```swift
public final class SystemWritablePasteboard: WritablePasteboard {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func writeText(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    public func writeFileURL(_ url: URL) {
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }
}

public final class SystemPasteEventSender: PasteEventSender {
    public init() {}

    public func sendPasteShortcut() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyDown?.flags = [.maskCommand]
        keyUp?.flags = [.maskCommand]
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 4: Run paste tests**

Run:

```bash
swift test --filter PasteActionServiceTests
```

Expected: paste action tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacToolsCore/Paste Tests/MacToolsCoreTests/PasteActionServiceTests.swift
git commit -m "feat: restore clipboard items for paste"
```

## Task 10: Permissions Service And Settings UI

**Files:**
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/Permissions/PermissionService.swift`
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/UI/SettingsView.swift`
- Test: `/Users/bytedance/Documents/mytools/Tests/MacToolsCoreTests/PermissionServiceTests.swift`

- [ ] **Step 1: Write permission model tests**

```swift
import XCTest
@testable import MacToolsCore

final class PermissionServiceTests: XCTestCase {
    func testSummaryDisablesSuperRightClickWithoutAccessibility() {
        let service = PermissionService(checker: FakePermissionChecker(accessibility: false, inputMonitoring: true))

        let summary = service.summary()

        XCTAssertFalse(summary.canUseSuperRightClick)
        XCTAssertEqual(summary.missingPermissions, [.accessibility])
    }
}
```

- [ ] **Step 2: Implement permission service**

```swift
import AppKit

public enum AppPermission: String, Equatable {
    case accessibility
    case inputMonitoring
}

public struct PermissionSummary: Equatable {
    public var hasAccessibility: Bool
    public var hasInputMonitoring: Bool

    public var canUseSuperRightClick: Bool {
        hasAccessibility
    }

    public var missingPermissions: [AppPermission] {
        var result: [AppPermission] = []
        if !hasAccessibility { result.append(.accessibility) }
        if !hasInputMonitoring { result.append(.inputMonitoring) }
        return result
    }
}

public protocol PermissionChecking {
    func hasAccessibilityPermission() -> Bool
    func hasInputMonitoringPermission() -> Bool
}

public final class PermissionService {
    private let checker: PermissionChecking

    public init(checker: PermissionChecking) {
        self.checker = checker
    }

    public func summary() -> PermissionSummary {
        PermissionSummary(
            hasAccessibility: checker.hasAccessibilityPermission(),
            hasInputMonitoring: checker.hasInputMonitoringPermission()
        )
    }

    public func openSystemSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
```

- [ ] **Step 3: Implement system checker**

```swift
public final class SystemPermissionChecker: PermissionChecking {
    public init() {}

    public func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    public func hasInputMonitoringPermission() -> Bool {
        true
    }
}
```

- [ ] **Step 4: Add settings view**

```swift
import SwiftUI

public struct SettingsView: View {
    public let settings: AppSettings
    public let permissions: PermissionSummary
    public let openSystemSettings: () -> Void

    public init(settings: AppSettings, permissions: PermissionSummary, openSystemSettings: @escaping () -> Void) {
        self.settings = settings
        self.permissions = permissions
        self.openSystemSettings = openSystemSettings
    }

    public var body: some View {
        Form {
            Section("Shortcuts") {
                Text("Main Panel: \(settings.mainPanelShortcut.displayValue)")
                Text("Clipboard: \(settings.clipboardShortcut.displayValue)")
            }
            Section("Clipboard") {
                Text("Recording: \(settings.clipboard.isRecordingEnabled ? "Enabled" : "Paused")")
                Text("Max History: \(settings.clipboard.maxHistoryCount)")
            }
            Section("Permissions") {
                Text("Accessibility: \(permissions.hasAccessibility ? "Granted" : "Missing")")
                Button("Open System Settings", action: openSystemSettings)
            }
        }
        .padding()
    }
}
```

- [ ] **Step 5: Run permission tests**

Run:

```bash
swift test --filter PermissionServiceTests
```

Expected: permission model tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/MacToolsCore/Permissions Sources/MacToolsCore/UI/SettingsView.swift Tests/MacToolsCoreTests/PermissionServiceTests.swift
git commit -m "feat: add permission status and settings view"
```

## Task 11: Translation SPI And Baidu Stub

**Files:**
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/Translation/TranslationProvider.swift`
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/Translation/BaiduTranslationProvider.swift`
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/Translation/TranslationService.swift`
- Test: `/Users/bytedance/Documents/mytools/Tests/MacToolsCoreTests/TranslationServiceTests.swift`

- [ ] **Step 1: Write translation tests**

```swift
import XCTest
@testable import MacToolsCore

final class TranslationServiceTests: XCTestCase {
    func testBaiduStubReportsMissingConfiguration() async {
        let service = TranslationService(provider: BaiduTranslationProvider(configuration: nil))

        let result = await service.translateToChinese("hello")

        XCTAssertEqual(result, .failure(.providerNotConfigured))
    }
}
```

- [ ] **Step 2: Implement translation SPI**

```swift
import Foundation

public struct TranslationRequest: Equatable {
    public var text: String
    public var sourceLanguage: String?
    public var targetLanguage: String
}

public struct TranslationResponse: Equatable {
    public var translatedText: String
    public var providerID: String
}

public enum TranslationError: Error, Equatable {
    case providerNotConfigured
    case networkUnavailable
    case providerFailure(String)
}

public protocol TranslationProvider {
    var providerID: String { get }
    func translate(_ request: TranslationRequest) async -> Result<TranslationResponse, TranslationError>
}
```

- [ ] **Step 3: Implement Baidu stub and service**

```swift
import Foundation

public struct BaiduTranslationConfiguration: Equatable {
    public var appID: String
    public var secret: String
}

public final class BaiduTranslationProvider: TranslationProvider {
    public let providerID = "baidu"
    private let configuration: BaiduTranslationConfiguration?

    public init(configuration: BaiduTranslationConfiguration?) {
        self.configuration = configuration
    }

    public func translate(_ request: TranslationRequest) async -> Result<TranslationResponse, TranslationError> {
        guard configuration != nil else {
            return .failure(.providerNotConfigured)
        }
        return .failure(.providerFailure("Baidu API wiring is waiting for supplied credentials and endpoint details."))
    }
}

public final class TranslationService {
    private let provider: TranslationProvider

    public init(provider: TranslationProvider) {
        self.provider = provider
    }

    public func translateToChinese(_ text: String) async -> Result<TranslationResponse, TranslationError> {
        await provider.translate(
            TranslationRequest(text: text, sourceLanguage: nil, targetLanguage: "zh")
        )
    }
}
```

- [ ] **Step 4: Run translation tests**

Run:

```bash
swift test --filter TranslationServiceTests
```

Expected: translation tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacToolsCore/Translation Tests/MacToolsCoreTests/TranslationServiceTests.swift
git commit -m "feat: add translation provider spi"
```

## Task 12: Right-Click State Machine And Selection Capture

**Files:**
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/RightClick/RightClickEvent.swift`
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/RightClick/RightClickStateMachine.swift`
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/RightClick/SelectionCaptureService.swift`
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/RightClick/SuperRightClickService.swift`
- Test: `/Users/bytedance/Documents/mytools/Tests/MacToolsCoreTests/RightClickStateMachineTests.swift`

- [ ] **Step 1: Write state machine tests**

```swift
import XCTest
@testable import MacToolsCore

final class RightClickStateMachineTests: XCTestCase {
    func testShortPressDoesNotTriggerSuperRightClick() {
        var machine = RightClickStateMachine(thresholdMilliseconds: 600)
        machine.handle(.pressed(atMilliseconds: 0))
        let result = machine.handle(.released(atMilliseconds: 200))
        XCTAssertEqual(result, .allowSystemMenu)
    }

    func testLongPressTriggersCustomAction() {
        var machine = RightClickStateMachine(thresholdMilliseconds: 600)
        machine.handle(.pressed(atMilliseconds: 0))
        let result = machine.handle(.timerFired(atMilliseconds: 601))
        XCTAssertEqual(result, .triggerSuperRightClick)
    }
}
```

- [ ] **Step 2: Implement state machine**

```swift
import Foundation

public enum RightClickEvent: Equatable {
    case pressed(atMilliseconds: Int)
    case released(atMilliseconds: Int)
    case timerFired(atMilliseconds: Int)
}

public enum RightClickDecision: Equatable {
    case none
    case allowSystemMenu
    case triggerSuperRightClick
}

public struct RightClickStateMachine {
    private let thresholdMilliseconds: Int
    private var pressStartMilliseconds: Int?
    private var didTrigger = false

    public init(thresholdMilliseconds: Int) {
        self.thresholdMilliseconds = thresholdMilliseconds
    }

    @discardableResult
    public mutating func handle(_ event: RightClickEvent) -> RightClickDecision {
        switch event {
        case .pressed(let at):
            pressStartMilliseconds = at
            didTrigger = false
            return .none
        case .released:
            defer { pressStartMilliseconds = nil }
            return didTrigger ? .none : .allowSystemMenu
        case .timerFired(let at):
            guard let start = pressStartMilliseconds, !didTrigger else {
                return .none
            }
            if at - start >= thresholdMilliseconds {
                didTrigger = true
                return .triggerSuperRightClick
            }
            return .none
        }
    }
}
```

- [ ] **Step 3: Implement selection capture boundary**

```swift
import Foundation

public protocol SelectionCapturing {
    func captureSelection() -> ClipboardPayload
}

public final class SelectionCaptureService: SelectionCapturing {
    private let pasteboard: PasteboardClient
    private let pasteSender: PasteEventSender

    public init(pasteboard: PasteboardClient, pasteSender: PasteEventSender) {
        self.pasteboard = pasteboard
        self.pasteSender = pasteSender
    }

    public func captureSelection() -> ClipboardPayload {
        pasteSender.sendPasteShortcut()
        Thread.sleep(forTimeInterval: 0.08)
        return pasteboard.readPayload()
    }
}
```

- [ ] **Step 4: Implement service shell**

```swift
import Foundation

public final class SuperRightClickService {
    private var stateMachine: RightClickStateMachine
    private let selectionCapture: SelectionCapturing
    private let classifier: ClipboardClassifier
    private let translationService: TranslationService

    public init(
        settings: SuperRightClickSettings,
        selectionCapture: SelectionCapturing,
        classifier: ClipboardClassifier,
        translationService: TranslationService
    ) {
        self.stateMachine = RightClickStateMachine(thresholdMilliseconds: settings.longPressMilliseconds)
        self.selectionCapture = selectionCapture
        self.classifier = classifier
        self.translationService = translationService
    }

    public func handleDecision(_ decision: RightClickDecision, sourceApp: String?) async -> ClipboardItem? {
        guard decision == .triggerSuperRightClick else {
            return nil
        }
        let payload = selectionCapture.captureSelection()
        let item = classifier.classify(payload: payload, sourceApp: sourceApp)
        if item.kind == .text, let text = item.text {
            _ = await translationService.translateToChinese(text)
        }
        return item
    }
}
```

- [ ] **Step 5: Run right-click tests**

Run:

```bash
swift test --filter RightClickStateMachineTests
```

Expected: right-click state machine tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/MacToolsCore/RightClick Tests/MacToolsCoreTests/RightClickStateMachineTests.swift
git commit -m "feat: add super right click state machine"
```

## Task 13: File And Terminal Actions

**Files:**
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/FileActions/FileActionService.swift`
- Create: `/Users/bytedance/Documents/mytools/Sources/MacToolsCore/UI/ContextActionView.swift`
- Test: `/Users/bytedance/Documents/mytools/Tests/MacToolsCoreTests/FileActionServiceTests.swift`

- [ ] **Step 1: Write file action tests**

```swift
import XCTest
@testable import MacToolsCore

final class FileActionServiceTests: XCTestCase {
    func testTerminalCommandUsesBuiltInTerminal() {
        let service = FileActionService(workspace: FakeWorkspace())
        let command = service.terminalOpenCommand(for: URL(fileURLWithPath: "/Users/bytedance/Documents"))

        XCTAssertEqual(command, "open -a Terminal /Users/bytedance/Documents")
    }
}
```

- [ ] **Step 2: Implement file actions**

```swift
import AppKit
import Foundation

public protocol WorkspaceOpening {
    func open(_ url: URL)
    func reveal(_ url: URL)
}

public final class FileActionService {
    private let workspace: WorkspaceOpening

    public init(workspace: WorkspaceOpening) {
        self.workspace = workspace
    }

    public func copyPath(item: ClipboardItem, pasteboard: WritablePasteboard) throws {
        guard let path = item.originalPath else {
            throw FileActionError.missingPath
        }
        pasteboard.writeText(path)
    }

    public func openTerminal(at folderURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", folderURL.path]
        try? process.run()
    }

    public func terminalOpenCommand(for folderURL: URL) -> String {
        "open -a Terminal \(folderURL.path)"
    }

    public func revealInFinder(_ fileURL: URL) {
        workspace.reveal(fileURL)
    }
}

public enum FileActionError: Error, Equatable {
    case missingPath
}

public final class SystemWorkspaceOpening: WorkspaceOpening {
    public init() {}

    public func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    public func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
```

- [ ] **Step 3: Implement context action view**

```swift
import SwiftUI

public struct ContextActionView: View {
    public let item: ClipboardItem
    public let copyPath: () -> Void
    public let openTerminal: () -> Void
    public let revealInFinder: () -> Void

    public init(
        item: ClipboardItem,
        copyPath: @escaping () -> Void,
        openTerminal: @escaping () -> Void,
        revealInFinder: @escaping () -> Void
    ) {
        self.item = item
        self.copyPath = copyPath
        self.openTerminal = openTerminal
        self.revealInFinder = revealInFinder
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.displayTitle).font(.headline)
            Button("Copy Path", action: copyPath)
            if item.kind == .folder {
                Button("Open in Terminal", action: openTerminal)
            }
            if item.kind == .file || item.kind == .imageFile {
                Button("Reveal in Finder", action: revealInFinder)
            }
        }
        .padding(14)
        .frame(width: 260)
    }
}
```

- [ ] **Step 4: Run file action tests**

Run:

```bash
swift test --filter FileActionServiceTests
```

Expected: file action tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacToolsCore/FileActions Sources/MacToolsCore/UI/ContextActionView.swift Tests/MacToolsCoreTests/FileActionServiceTests.swift
git commit -m "feat: add file context actions"
```

## Task 14: Packaging Script And Manual Verification Checklist

**Files:**
- Create: `/Users/bytedance/Documents/mytools/scripts/package_app.sh`
- Create: `/Users/bytedance/Documents/mytools/docs/manual-verification.md`

- [ ] **Step 1: Create packaging script**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/build/MacTools.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

swift build -c release --product MacTools

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$BUILD_DIR/MacTools" "$MACOS_DIR/MacTools"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>MacTools</string>
  <key>CFBundleIdentifier</key>
  <string>local.mactools.mvp</string>
  <key>CFBundleName</key>
  <string>MacTools</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

echo "$APP_DIR"
```

- [ ] **Step 2: Make script executable**

Run:

```bash
chmod +x scripts/package_app.sh
```

- [ ] **Step 3: Create manual verification doc**

```markdown
# Manual Verification

- Launch with `swift run MacTools`.
- Confirm menu bar item appears as `MT`.
- Confirm Dock icon does not appear.
- Use `Option + Space` to open the main panel.
- Use `Option + 1` to open clipboard history.
- Copy text and confirm it appears in clipboard search.
- Copy a file and confirm filename/path appears.
- Copy a folder and confirm folder actions show Copy Path and Open in Terminal.
- Copy image data and confirm it is stored in the app cache.
- Select a clipboard item and press Enter; confirm it copies and attempts paste.
- Use Cmd+Enter; confirm it copies without sending paste.
- Short right-click in Finder; confirm the system menu appears.
- Long right-click a selected folder; confirm the context action window appears.
- Long right-click selected text before Baidu credentials are configured; confirm the translation service reports unconfigured state.
- Open settings and confirm permission status is visible.
- Build app bundle with `scripts/package_app.sh`.
- Launch `build/MacTools.app`.
```

- [ ] **Step 4: Run full tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 5: Build release bundle**

Run:

```bash
scripts/package_app.sh
```

Expected: prints `/Users/bytedance/Documents/mytools/build/MacTools.app`.

- [ ] **Step 6: Commit**

```bash
git add scripts/package_app.sh docs/manual-verification.md
git commit -m "chore: add packaging and verification docs"
```

## Execution Order

1. Task 1: scaffold.
2. Task 2: settings.
3. Task 3: clipboard classification.
4. Task 4: SQLite repository.
5. Task 5: file cache.
6. Task 6: clipboard recording.
7. Task 7: panel UI.
8. Task 8: hotkeys.
9. Task 9: paste actions.
10. Task 10: permissions and settings.
11. Task 11: translation SPI.
12. Task 12: super right-click state machine and capture shell.
13. Task 13: file and Terminal actions.
14. Task 14: packaging and manual verification.

## Self-Review

Spec coverage:

- Menu bar resident app: Tasks 1 and 14.
- Hidden Dock icon: Tasks 1 and 14.
- `Option + Space`, `Option + 1`, reserved hotkeys: Tasks 2 and 8.
- Clipboard history for text, files, folders, image file paths, raw image data: Tasks 3-6.
- Clipboard search, pinned, favorites: Tasks 4 and 7.
- Copy-only and copy-and-paste: Task 9.
- Super right click with configurable long press: Tasks 2 and 12.
- Text translation to Chinese through SPI: Task 11 and Task 12.
- Folder/file action window: Task 13.
- Terminal.app integration: Task 13.
- Permission guidance: Task 10.
- Local SQLite and App Support cache: Tasks 4 and 5.

Placeholder scan:

- The plan intentionally includes a Baidu translation stub because the approved MVP excludes live API integration until credentials are supplied. That stub has exact behavior: return `providerNotConfigured` when credentials are absent and provider failure text when configuration exists without endpoint wiring.

Type consistency:

- `ClipboardItem`, `ClipboardPayload`, `AppSettings`, `HotKeyBinding`, `TranslationService`, `PasteActionService`, and `RightClickStateMachine` names are introduced before later tasks reference them.
- Repository and service names match the approved architecture diagram and design spec.

