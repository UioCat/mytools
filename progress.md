# Progress Log

## Session: 2026-07-20

### Phase 1: Baseline & Approved Design
- **Status:** complete
- Actions taken:
  - 核对现有统一存储、CloudKit、Core 同步模型、设置入口和打包脚本。
  - 比较事件日志、每记录分片、每设备紧凑快照三种方案。
  - 与用户确认每设备紧凑快照、全局普通历史 500、默认 512 MiB。
  - 写入并自审 iCloud Drive 同步设计，提交为 `03f8bb8`。
- Files created/modified:
  - `docs/superpowers/specs/2026-07-20-icloud-drive-sync-design.md`
  - `docs/superpowers/specs/2026-07-16-storage-and-icloud-sync-design.md`

### Phase 2: Transport-neutral Core
- **Status:** complete
- Actions taken:
  - 创建可恢复实施计划。
  - 增加稳定快照模型、默认 512 MiB 容量策略和 stale eviction 失效规则。
  - 增加文件同步本机覆盖项、V7 receipt/GC 状态和传输无关本地快照仓库。
  - 聚焦编译确认旧 `SettingsView` 仍引用 CloudKit 账号状态，下一步整体替换为文件夹状态。
  - 完成全局 500、512 MiB、64 MiB 单图、stale eviction、24 小时 GC 和 tombstone 确认压缩。
- Files created/modified:
  - `task_plan.md`
  - `findings.md`
  - `progress.md`
  - `Sources/MacToolsCore/Sync/DriveSyncModels.swift`
  - `Sources/MacToolsCore/Sync/SyncLocalRepository.swift`
  - `Tests/MacToolsCoreTests/DriveSyncModelsTests.swift`

### Phase 3-5: File Transport, Runtime, Settings & Packaging
- **Status:** complete
- Actions taken:
  - 实现协议目录、共享内容对象、每设备快照、manifest 最后提交与摘要读回。
  - 使用 `NSFileCoordinator`、security-scoped bookmark 和 30 秒周期扫描接入 App。
  - 设置卡片增加目录选择、用量、容量档位、打开目录、立即同步和 reset。
  - 删除 CloudKit coordinator/mapper、远程通知、entitlement 和签名门禁。
  - 更新 README、打包测试和手工验收清单。

### Phase 6: Verification
- **Status:** complete
- Actions taken:
  - 聚焦验证覆盖双数据库收敛、快照原子提交、损坏副本隔离、共享对象修复、本地图片缺失、容量/GC、代次 tombstone 和 Keychain 并发。
  - 最终全量 `swift test`：327 项通过。
  - ad-hoc 打包、严格签名校验和启动通过；成品不含 CloudKit/iCloud/APNs entitlement 或 Provisioning Profile。
  - 真实统一数据库只读校验通过：完整性正常、9 个迁移、普通历史稳定为 500、数据库权限为 `0600`，Payload 行数与文件数一致。
  - 设置窗口浅色/深色状态已检查；真实双 Mac 的 iCloud Drive 传播保留为人工验收边界。

## Test Results
| Test | Input | Expected | Actual | Status |
| --- | --- | --- | --- | --- |
| 设计文档占位扫描 | `rg TBD/TODO/...` | 无占位 | 无匹配 | 通过 |
| 设计文档格式 | fence/尾随空格检查 | 平衡且无尾随空格 | 8 个 fence，检查通过 | 通过 |
| Core 快照与容量策略 | `swift test --filter DriveSyncModelsTests` | 6 项通过 | 6 项通过 | 通过 |
| 文件协议、损坏隔离与容量聚焦测试 | Drive/Sync filters | 全部通过 | 全部通过 | 通过 |
| Keychain 阻塞读取与保存顺序 | `swift test --filter CredentialAccessCoordinatorTests` | 新保存最终胜出 | 2 项通过 | 通过 |
| 全量单元测试 | `swift test` | 全部通过 | 327 项通过 | 通过 |
| ad-hoc 成品 | `MACOS_FORCE_ADHOC_SIGNING=1 scripts/rebuild_and_run_app.sh` | 可构建并启动 | 通过 | 通过 |
| 真实统一数据库 | SQLite 只读聚合与 integrity check | 无损且普通历史为 500 | 通过 | 通过 |

## Error Log
| Timestamp | Error | Attempt | Resolution |
| --- | --- | --- | --- |
| 2026-07-20 | zsh unmatched quote（只读检索） | 1 | 拆分命令后成功 |
| 2026-07-20 | 文档 patch 预期行未命中 | 1 | 检查实际内容，确认无需修改 |
| 2026-07-20 | `writing-plans` skill 不可用 | 1 | 使用 `planning-with-files` 替代 |
| 2026-07-20 | 旧 CloudKit UI 状态枚举导致编译失败 | 1 | 根因已确认，更新为文件夹同步状态模型 |
| 2026-07-20 | 进度日志 patch 预期段落未命中 | 1 | 读取实际文件后按现有分节更新 |
| 2026-07-20 | 设置页组合 patch 上下文未命中 | 1 | 拆为小范围 patch 继续 |
| 2026-07-20 | 文件存储测试编译被旧 CloudKit Coordinator 阻断 | 1 | 新 Core 已编译；下一步新增 Drive Coordinator 并移除 CloudKit 文件 |
| 2026-07-20 | Drive Coordinator 淘汰 ID 集合无法推断泛型 | 1 | 明确 `Set<String>`；其余新 App 接线已通过编译 |
| 2026-07-20 | 打包测试转义字符串 patch 首次未命中 | 1 | 按实际源文件单行内容替换为简单断言 |
| 2026-07-20 | tombstone export 闭包返回类型错误 | 1 | 在 UPDATE 后的 Row 查询增加显式 `return` |
| 2026-07-20 | `osascript` 不允许发送按键 | 1 | 不扩大权限；设置页真实打开改为人工验收，继续做离屏/源码检查 |

## 5-Question Reboot Check
| Question | Answer |
| --- | --- |
| Where am I? | 实现与本机验证完成 |
| Where am I going? | 真实双 Mac iCloud Drive 人工验收 |
| What's the goal? | 免费账号可用的 iCloud Drive 多设备同步 |
| What have I learned? | 见 `findings.md` |
| What have I done? | 文件同步后端、容量/GC、运行时、设置和打包已完成，327 项测试通过 |
