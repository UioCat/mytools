# iCloud Manifest 冲突恢复与幂等发布实施计划

**目标：** 修复同一 revision 失败重试持续生成快照目录的问题，使副本所有者能够安全收敛
单调 manifest 冲突，并在无法证明安全时保留数据和显示明确状态。

**规格：** `docs/superpowers/specs/2026-08-23-icloud-manifest-conflict-recovery-design.md`

**技术栈：** Swift 5.10、Foundation、NSFileCoordinator、NSFileVersion、GRDB、XCTest、macOS 26+

## 全局约束

- 不修改同步协议版本、剪贴板筛选、内容 ID、代际、receipt、tombstone 或设备移除语义。
- 只有副本所有者自动恢复自己的 manifest；其他设备只报告冲突。
- manifest 普通内容更新在确切文件 URL 上使用普通协调写，不误用 `.forReplacing`。
- manifest 替换一旦开始，快照状态默认不确定并保留；无台账历史目录不自动删除。
- 只有发布本轮 draft，或发现发布身份相同（允许时间和设备显示名不同）的已发布 draft，才能确认 outbox。
- 当前实现不新增现场诊断日志；未来日志不得包含剪贴板内容、真实同步路径、设备名称、完整设备 ID 或凭据。

---

### 任务 1：建立纯冲突决策和文件协调接口

**文件：**

- 新增：`Sources/MacToolsCore/Sync/SyncManifestConflictResolver.swift`
- 新增：`Sources/MacToolsCore/Sync/SyncFileCoordinator.swift`
- 新增：`Tests/MacToolsCoreTests/SyncManifestConflictResolverTests.swift`
- 新增：`Tests/MacToolsCoreTests/SyncFileCoordinatorTests.swift`

- [x] 先写失败测试，覆盖 1885/1887 祖先、不可比较分叉、自身向量不变量、损坏候选、
  `verifiedBySupersededLedger` 单向例外和版本变化放弃。
- [x] 定义不依赖 `NSFileVersion` 的候选、决策和同步文件协调协议。
- [x] 提供仅用于普通本地文件系统和单元测试的直接实现。
- [x] 运行 `swift test --filter 'SyncManifestConflictResolverTests|SyncFileCoordinatorTests'`。

### 任务 2：实现发布台账和事务提交

**文件：**

- 修改：`Sources/MacToolsCore/Storage/ClipboardDatabase.swift`
- 新增：`Sources/MacToolsCore/Sync/SyncSnapshotPublicationLedger.swift`
- 修改：`Sources/MacToolsCore/Sync/SyncLocalRepository.swift`
- 修改：`Sources/MacToolsCore/Settings/DeviceOverrideRepository.swift`
- 新增：`Tests/MacToolsCoreTests/SyncSnapshotPublicationLedgerTests.swift`

- [x] 新增 V11 SQLite 迁移和旧数据库安全升级测试。
- [x] 实现 `prepared → publicationUncertain → published → superseded → reclaimed` 状态约束。
- [x] 把发布确认、outbox 确认、revision 和 seenRevisions 更新放入同一数据库事务。
- [x] 覆盖回读失败、重启恢复、摘要不匹配和 store/generation 切换。
- [x] 运行 `swift test --filter 'SyncSnapshotPublicationLedgerTests|SyncLocalRepositoryTests|SettingsStoreTests'`。

### 任务 3：使 DriveSyncStore 发布幂等且安全恢复冲突

**文件：**

- 修改：`Sources/MacToolsCore/Sync/DriveSyncStore.swift`
- 修改：`Sources/MacToolsCore/Sync/DriveSyncModels.swift`
- 修改：`Tests/MacToolsCoreTests/DriveSyncStoreTests.swift`

- [x] 先写失败测试证明同 revision、同内容连续失败或重试只产生一个确定性目录。
- [x] 在创建快照前预检 manifest 冲突；无法收敛时零目录变更。
- [x] 用 generation、revision 和三个摘要组合生成确定性目录并校验复用内容。
- [x] 发布前记录 `publicationUncertain`；回读失败不删除最终快照。
- [x] 返回 `publishedDraft`、`alreadyPublishedDraft`、`adoptedNewerRemote` 三类结果。
- [x] 自动清理仅处理台账证明 `prepared` 或 `superseded` 的目录，每轮最多 256 个且限时 2 秒；
  回收后的 `reclaimed` 证据继续保留。
- [x] 运行 `swift test --filter DriveSyncStoreTests`。

### 任务 4：接入 Runner 的结果语义和冲突状态

**文件：**

- 修改：`Sources/MacToolsCore/Sync/DriveSyncCycleRunner.swift`
- 修改：`Sources/MacToolsCore/Settings/AppSettings.swift`
- 修改：`Sources/MacToolsCore/UI/Settings/SyncSettingsEditor.swift`
- 修改：`Tests/MacToolsCoreTests/DriveSyncCycleRunnerTests.swift`
- 修改：`Tests/MacToolsCoreTests/SettingsStoreTests.swift`

- [x] 只有 `publishedDraft` 和 `alreadyPublishedDraft` 走事务确认。
- [x] `adoptedNewerRemote` 只追平进度、失效缓存并立即补跑，不确认 outbox。
- [x] 将不可收敛 manifest 映射为 `SyncStatus.conflictNeedsAttention` 和明确中文文案。
- [x] 覆盖错误映射、状态文案、观察缓存和 outbox 保留。
- [x] 运行 `swift test --filter 'DriveSyncCycleRunnerTests|SettingsStoreTests'`。

### 任务 5：实现 macOS 文件版本协调和跨进程单写者

**文件：**

- 新增：`Sources/MacTools/Platform/Sync/ICloudSyncFileCoordinator.swift`
- 新增：`Sources/MacTools/Platform/Sync/SyncStoreProcessLock.swift`
- 修改：`Sources/MacTools/Platform/Sync/ICloudDriveSyncCoordinator.swift`
- 修改：`Tests/MacToolsCoreTests/ICloudDriveSyncCoordinatorSourceTests.swift`

- [x] 对当前 manifest 和每个历史 `version.url` 执行协调读取。
- [x] 在同一确切 manifest 协调写区间重新枚举、决策、恢复获胜版本、回读并移除旧版本。
- [x] 用同步根目录派生本地锁文件；一个进程写入时其他进程跳过本轮且不发布失败状态。
- [x] 保持凭据 replica 仅自动消除字节完全相同冲突。
- [x] 运行相关 SourceTests 和严格并发构建。

### 任务 6：完整验证、独立 Review、提交和发布判断

- [x] 运行全部新增与受影响聚焦测试，再运行完整 `swift test`。
- [x] 运行严格并发构建：

  ```sh
  swift build --product MacTools -Xswiftc -strict-concurrency=complete -Xswiftc -warn-concurrency
  ```

- [ ] 运行 `scripts/package_app.sh`，在隔离目录重放冲突和重复失败。
- [ ] 运行 `scripts/rebuild_and_run_app.sh`，检查设置页冲突状态和既有 Liquid Glass 外观。
- [x] 不经再次人工确认，不对真实 iCloud 目录执行冲突消除、隔离或删除。
- [ ] 执行 `git diff --check`、敏感信息扫描、独立代码 Review 和独立发布判断。
- [ ] 修复所有 P0-P2 并复审，随后仅提交本任务文件、推送当前分支；按发布门禁决定是否发版。
