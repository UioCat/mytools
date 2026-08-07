// `ClipboardSnapshotSampler` 的轻量剪贴板快照实现。
// 只负责稳定读取当前剪贴板并推进采样游标，不执行分类、图片转码或持久化。

import Foundation

/// 一次稳定剪贴板读取产生的不可变值，可安全地排队等待后续持久化。
public struct ClipboardSnapshot: Equatable, Sendable {
    public let payload: ClipboardPayload
    public let sourceApp: String?
    public let capturedAt: Date
    public let changeCount: Int
    public let skippedChangeCount: Int

    public init(
        payload: ClipboardPayload,
        sourceApp: String?,
        capturedAt: Date,
        changeCount: Int,
        skippedChangeCount: Int
    ) {
        self.payload = payload
        self.sourceApp = sourceApp
        self.capturedAt = capturedAt
        self.changeCount = changeCount
        self.skippedChangeCount = skippedChangeCount
    }
}

/// 通过 `changeCount` 高频采样剪贴板，并在内容读取期间发生变化时立即重试。
public final class ClipboardSnapshotSampler {
    private let pasteboard: PasteboardClient
    private let maximumReadAttempts: Int
    private let now: () -> Date
    private var lastChangeCount: Int
    private var isRecordingEnabled: Bool

    public init(
        pasteboard: PasteboardClient,
        isRecordingEnabled: Bool,
        maximumReadAttempts: Int = 3,
        now: @escaping () -> Date = Date.init
    ) {
        self.pasteboard = pasteboard
        self.isRecordingEnabled = isRecordingEnabled
        self.maximumReadAttempts = max(1, maximumReadAttempts)
        self.now = now
        self.lastChangeCount = pasteboard.changeCount
    }

    /// 热更新录制开关；暂停期间的变化会在下一次采样时被直接跳过。
    public func updateRecordingEnabled(_ isRecordingEnabled: Bool) {
        self.isRecordingEnabled = isRecordingEnabled
    }

    /// 返回一次稳定快照。连续写入导致读取前后计数不一致时，立即读取最新内容。
    public func captureOnce(sourceApp: String?) -> ClipboardSnapshot? {
        let observedChangeCount = pasteboard.changeCount

        guard isRecordingEnabled else {
            lastChangeCount = observedChangeCount
            return nil
        }
        guard observedChangeCount != lastChangeCount else {
            return nil
        }

        for _ in 0..<maximumReadAttempts {
            let changeCountBeforeRead = pasteboard.changeCount
            let payload = pasteboard.readSnapshotPayload()
            let changeCountAfterRead = pasteboard.changeCount

            guard changeCountBeforeRead == changeCountAfterRead else {
                continue
            }

            let skippedChangeCount = Self.skippedChanges(
                from: lastChangeCount,
                to: changeCountAfterRead
            )
            lastChangeCount = changeCountAfterRead
            return ClipboardSnapshot(
                payload: payload,
                sourceApp: sourceApp,
                capturedAt: now(),
                changeCount: changeCountAfterRead,
                skippedChangeCount: skippedChangeCount
            )
        }

        return nil
    }

    private static func skippedChanges(from previous: Int, to current: Int) -> Int {
        guard current > previous else {
            return 0
        }
        return max(0, current - previous - 1)
    }
}
