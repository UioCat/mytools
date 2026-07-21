# Task Plan: iCloud Drive 多设备同步实现

## Goal
将当前需要付费 Capability 的 CloudKit 同步替换为用户选择 iCloud Drive 文件夹的多设备同步，保持本地 SQLite 为运行时数据源，并落实全局普通历史 500 条、默认稳态目录 512 MiB、SHA-256 去重、配置合并、墓碑和安全 GC。

## Current Phase
Complete

## Phases

### Phase 1: Baseline & Approved Design
- [x] 核对现有本地存储、CloudKit 协调器、Core 同步状态和设置入口
- [x] 确认每设备紧凑快照 + 共享内容对象协议
- [x] 确认 512 MiB 默认容量、全局 500 条和 64 MiB 单图边界
- [x] 技术方案完成自审并由用户确认开始执行
- **Status:** complete

### Phase 2: Transport-neutral Core
- [x] 将 CloudKit 命名重构为传输无关同步模型
- [x] 实现快照、manifest、内容对象、容量策略和淘汰决策
- [x] 增加确定性 Core 单元测试
- **Status:** complete

### Phase 3: iCloud Drive File Transport
- [x] 实现同步根目录布局、紧凑 JSON、原子写入和读回摘要校验
- [x] 实现文件下载状态、bookmark/目录解析和周期扫描适配边界
- [x] 使用两个临时客户端验证损坏文件、内容收敛和去重
- **Status:** complete

### Phase 4: Database & Runtime Integration
- [x] 增加 V7-V9 文件同步、因果 tombstone 与命名迁移
- [x] 将 AppEnvironment 切换到 iCloud Drive 协调器
- [x] 移除 CloudKit 账号、推送和远程通知运行时路径
- **Status:** complete

### Phase 5: Settings & Packaging
- [x] 在现有数据与同步卡片加入目录、容量、用量和状态入口
- [x] 移除 CloudKit entitlement、Container、Provisioning Profile 和 APNs 打包门禁
- [x] 更新 README 与手工验收清单
- **Status:** complete

### Phase 6: Verification
- [x] 运行聚焦测试并修复问题
- [x] 运行 `swift test`
- [x] 打包、签名、启动和检查真实本地统一存储不受影响
- [x] 使用临时共享目录模拟双设备完整同步
- **Status:** complete

### Phase 7: Delivery
- [x] 复核需求与差异
- [x] 说明真实 iCloud 双机人工验收边界
- [x] 交付文件、测试和运行状态
- **Status:** complete

## Key Questions
1. 文件协议如何避免不同设备同时写同一可变文件？已确定每设备快照单写者。
2. 如何避免 iCloud 容量无限增长？已确定全局 500、稳态目录 512 MiB、单图 64 MiB、安全 GC。
3. 如何在免费/ad-hoc 构建中持久访问用户选择目录？使用目录 bookmark 与可注入文件协调边界。
4. 如何证明多设备收敛而不依赖真实 iCloud？两个独立数据库与同一临时同步根目录的集成测试。

## Decisions Made
| Decision | Rationale |
| --- | --- |
| 本地 SQLite 始终是运行时数据源 | 禁止共享 SQLite/WAL，避免文件同步损坏事务 |
| 每设备紧凑快照 | 单写者且文件数量有界，优于事件日志和每记录文件 |
| 共享 SHA-256 内容对象 | 跨设备去重并能校验完整性 |
| 512 MiB 稳态目录预算 | 控制用户 iCloud 占用；用户已确认默认值 |
| 收藏/置顶不自动删除 | 保留用户保护语义；容量满时暂停新增图片 |
| API Key 只存本机 Keychain | 不把敏感凭据写入普通 iCloud Drive 文件 |
| 不保留 CloudKit 后端 | 用户无付费会员且不要求兼容，可减少双后端复杂度 |

## Errors Encountered
| Error | Attempt | Resolution |
| --- | --- | --- |
| 设计检索命令出现 zsh unmatched quote | 1 | 拆分 `rg` 表达式后成功读取 |
| 删除重复文档行的 patch 未命中 | 1 | 核对实际文件后确认只是重叠 `sed` 输出，未重复修改 |
| `writing-plans` skill 不可用 | 1 | 使用 `planning-with-files` 作为可恢复计划替代 |
| Core 聚焦编译命中旧 CloudKit UI 状态枚举 | 1 | 根因是 `SyncStatus` 已替换而 `SettingsView` 仍引用账号/网络状态；按文件夹状态模型整体更新该卡片 |
| 进度日志 patch 预期段落未命中 | 1 | 读取实际分节后按现有结构更新 |
| 设置页大 patch 因上下文顺序未命中 | 1 | 拆为模型扩展、属性接线和编辑器替换三个小 patch |
| 文件存储聚焦编译命中旧 CloudKit Coordinator 状态 | 1 | Core 与新设置页已通过编译，失败边界精确收敛到待删除的 CloudKit App 层和旧 AppEnvironment 接线 |
| 新协调器 `Set(compactMap)` 元素类型推断失败 | 1 | 明确标注为 `Set<String>` 和闭包返回 `String?` |
| 打包测试多行字符串修正首次未命中 | 1 | 使用文件中的实际单行转义文本精确替换 |
| tombstone export 写事务闭包推断为 `Void` | 1 | 根因是新增 origin UPDATE 后末尾查询缺少显式 `return`；补齐返回值 |
| `osascript` 无辅助功能权限，无法注入 Option+Space | 1 | 不修改系统权限；改用 SwiftUI 离屏渲染/源码布局检查，并保留真实交互为人工验收边界 |

## Notes
- 工作树包含本任务前序统一存储和 CloudKit 实现，修改时只替换同步后端，不破坏已验证本地迁移。
- 声称完成前必须执行全量测试、打包检查和真实数据库只读校验。
