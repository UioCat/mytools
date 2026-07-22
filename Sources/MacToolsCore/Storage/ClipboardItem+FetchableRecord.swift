import Foundation
import GRDB

extension ClipboardItem: FetchableRecord {
    public init(row: Row) throws {
        let idValue: String = row["id"]
        guard let id = UUID(uuidString: idValue) else {
            throw ClipboardRecordError.invalidUUID(idValue)
        }

        let kindValue: String = row["kind"]
        guard let kind = ClipboardContentKind(rawValue: kindValue) else {
            throw ClipboardRecordError.invalidKind(kindValue)
        }

        self.init(
            id: id,
            kind: kind,
            displayTitle: row["displayTitle"],
            searchableText: row["searchableText"],
            text: row["text"],
            originalPath: row["originalPath"],
            cachedFilePath: row["cachedFilePath"],
            thumbnailPath: nil,
            sourceApp: row["sourceApp"],
            contentHash: row["contentHash"],
            createdAt: row["createdAt"],
            lastUsedAt: row["lastUsedAt"],
            useCount: row["useCount"],
            isPinned: row["isPinned"],
            isFavorite: row["isFavorite"],
            lastCapturedAt: row["lastCapturedAt"],
            retentionAt: row["retentionAt"],
            payloadID: row["payloadID"],
            syncGeneration: row["syncGeneration"],
            favoriteClock: ClipboardFieldClock(
                counter: row["favoriteClock"],
                deviceID: row["favoriteDeviceID"]
            ),
            pinnedClock: ClipboardFieldClock(
                counter: row["pinnedClock"],
                deviceID: row["pinnedDeviceID"]
            )
        )
    }
}

enum ClipboardRecordError: Error {
    case invalidUUID(String)
    case invalidKind(String)
}
