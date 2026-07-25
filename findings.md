# Findings & Decisions

## Requirements
- 免费 Apple Developer 账号或 ad-hoc 签名可使用。
- 用户选择 iCloud Drive 普通文件夹作为同步根目录。
- 同步文字、URL、原始剪贴板图片、收藏/置顶和账号级普通配置。
- 多设备可同时在线或离线修改并最终收敛。
- 全局普通云端历史最多 500 条。
- 稳态同步目录默认限制 512 MiB；单个图片最多 64 MiB。
- 收藏和置顶不自动删除；容量无法释放时暂停新增图片，其他同步继续。
- 本地 SQLite/Payload 不直接放入 iCloud Drive。
- Bailian API Key 不进入普通配置快照或内容对象；使用独立 AES-GCM replica 在同步目录中跨设备恢复。

## Research Findings
- 现有 `sync_outbox`、字段时钟、tombstone、DeviceReplica、重复 Record alias 和 Payload 生命周期均可复用。
- CloudKit 特有部分集中在 `CloudKitSyncCoordinator`、`CloudKitRecordMapper`、账号/system fields 表、AppEnvironment capability 门禁和打包 entitlements。
- 当前设置卡片已经具备同步开关、范围、状态、立即同步和删除云端数据入口，可在原层级内替换语义。
- 当前 ad-hoc 包主动关闭 CloudKit，真实本地数据库没有已启用的 CloudKit 会话。
- Apple 免费 Personal Team 不提供当前方案所需 CloudKit Container；用户选择普通 iCloud Drive 文件夹不依赖该 Capability。

## Technical Decisions
| Decision | Rationale |
| --- | --- |
| `protocol.json` + `replicas/<deviceID>` + `objects/sha256` | 协议可升级、单写者、内容去重 |
| manifest 最后提交 | 快照部分写入时其他设备继续使用上一 revision |
| compact sorted JSON | 无额外依赖、可诊断、比 pretty JSON 小 |
| 本地 staging 后协调替换 | 临时文件不占用远端稳态空间 |
| manifest 保存 `seenRevisions` | tombstone 仅在所有有效设备确认后压缩 |
| GC 遇到任一未下载/未验证快照即暂停 | 避免引用尚未到达时误删共享对象 |
| 单记录内容故障隔离 | 本地图片缺失或远端对象损坏不能阻塞文字、配置和删除同步 |
| 凭据独立加密 replica | 避免进入普通设置同步；本地缓存优先，删除用逻辑时钟墓碑收敛 |
| 公开固定材料派生 AES-GCM 密钥 | ad-hoc 重建和另一台 Mac 可直接解密；只防止明文误读，不抵御逆向 |
| 设置页沿用现有 Liquid Glass 卡片 | 保持产品信息架构和视觉语义一致 |

## Issues Encountered
| Issue | Resolution |
| --- | --- |
| 现有同步类型大量使用 Cloud 前缀 | Phase 2 先改为传输无关命名，再接文件后端 |
| CloudKit 删除是全局 Record 语义，文件后端是设备分片 | 删除和淘汰必须作为持久状态合并，不能只删除某个文件 |
| iCloud Drive 无可靠完整配额 API | 只显示 MacTools 目录逻辑占用，不冒充用户总剩余容量 |

## Resources
- `docs/superpowers/specs/2026-07-20-icloud-drive-sync-design.md`
- `Sources/MacToolsCore/Sync/SyncLocalRepository.swift`
- `Sources/MacToolsCore/Sync/DriveSyncStore.swift`
- `Sources/MacTools/App/Sync/ICloudDriveSyncCoordinator.swift`
- `Sources/MacToolsCore/UI/SettingsView.swift`
- Apple `NSFileCoordinator`, URL bookmark 与 ubiquitous item APIs。

## Visual Findings
- 设置入口沿用现有卡片与原生控件，不引入独立页面。
- 通过 UI 验证启动参数在真实打包 App 中检查浅色和深色设置页；同步目录、状态、用量、容量、设备和操作区均保持在原信息层级。
