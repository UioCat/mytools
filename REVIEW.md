# MacTools 全量代码审查报告

## 审查结论

| 项目 | 结果 |
| --- | --- |
| 审查日期 | 2026-07-26 |
| 代码基线 | `ffa2c498ac4fba489795050506ba23e5b4791a4c`（`main`，`v0.1.3`） |
| 总体结论 | **未通过：存在 7 项未解决 P1** |
| 问题统计 | P0：0；P1：7；P2：16；P3：3 |
| 自动测试 | 416 项通过，0 失败 |
| Swift 5 完整并发检查 | 通过，无警告 |
| Swift 6 语言模式 | 未通过；当前 GRDB `6.29.3` 先于项目源码触发并发安全错误 |
| 打包验证 | 未完成；依赖子模块下载发生 HTTP/2 连接重置，复验在同一下载阶段持续无进展后终止 |

当前实现已经具备较扎实的 Core 测试、存储迁移、内容寻址、文件权限和取消机制，但仍有三类发布前高风险：

1. 同步目录中的数据和设备没有来源认证，远端设置还能改变本机 API Key 的使用目标。
2. 超级右键、权限恢复、截图取消和同步切换存在明确的生命周期或过期结果问题。
3. 当前公开发布物使用宽泛代码要求和 ad-hoc 签名，不具备普通用户发行所需的身份与 Gatekeeper 信任链。

## 范围与方法

### 代码范围

| 范围 | 规模 | 审查重点 |
| --- | ---: | --- |
| `Sources/MacTools` | 22 个 Swift 文件 | AppKit 生命周期、运行时装配、TCC、Finder、事件监听、截图录屏 |
| `Sources/MacToolsCore` | 83 个 Swift 文件 | 业务状态、数据库、文件存储、同步、凭据、SwiftUI、可测试服务 |
| `Tests/MacToolsCoreTests` | 64 个 Swift 文件、416 个测试 | 行为覆盖、源码断言、确定性、关键缺口 |
| 工程与发布 | `Package.swift`、4 个脚本、1 个 GitHub Actions 工作流 | 依赖、签名、版本、DMG、发布门禁 |
| 文档与产品约定 | `AGENTS.md`、`README.md`、`docs/` | 实现、权限、隐私和人工验收是否一致 |

生产 Swift 代码约 21,861 行，测试约 9,777 行。审查采用全局模式扫描、关键调用链逐文件核对、编译测试、覆盖率分析，以及三个独立子审查域交叉复核：

- 架构、并发、生命周期与性能；
- 安全、隐私、凭据、存储、迁移与同步；
- AppKit/SwiftUI、TCC、Finder、ScreenCaptureKit、签名与可访问性。

### 风险等级

| 等级 | 定义 |
| --- | --- |
| P0 | 可直接造成严重数据泄露、不可恢复损坏或应用无法发布 |
| P1 | 常见路径中的错误结果、权限回归、核心功能不可用或高风险安全缺口 |
| P2 | 特定条件下的真实缺陷、资源泄漏、兼容性问题或必要测试缺口 |
| P3 | 非阻断，但有明确维护成本或低风险改进价值 |

## 风险总览

| 维度 | 状态 | 结论 |
| --- | --- | --- |
| 正确性与生命周期 | 高风险 | 超级右键和同步周期会发布过期结果 |
| 安全与隐私 | 高风险 | 同步数据无来源认证；凭据保护属于公开材料混淆；代码要求过宽 |
| 数据完整性 | 中风险 | 远端图片导入、跨存储凭据保存和历史副本生命周期存在缺口 |
| macOS 系统集成 | 高风险 | 授权返回不恢复监听；截图取消依赖额外权限 |
| 并发与性能 | 中风险 | 启动、剪贴板和 SwiftUI `body` 中存在同步 I/O |
| 测试与发布 | 中风险 | Core 覆盖较好，App 目标和真实系统边界缺少行为门禁 |
| 可维护性 | 中低风险 | Swift 6 迁移被旧依赖阻断，若干核心文件职责仍偏重 |

## P1：必须优先处理

### REV-P1-01：同步数据缺少来源认证，可把本机凭据发送到伪造 Endpoint

**位置**

- `Sources/MacToolsCore/Sync/DriveSyncModels.swift:493`
- `Sources/MacToolsCore/Sync/DriveSyncStore.swift:492`
- `Sources/MacToolsCore/Settings/PreferenceRepository.swift:139`
- `Sources/MacTools/App/AppEnvironment.swift:535`
- `Sources/MacToolsCore/Settings/AppSettings.swift:338`
- `Sources/MacToolsCore/Translation/BailianTranslationProvider.swift:72`
- `Sources/MacTools/App/AppEnvironment.swift:792`

**现象 / 原因**

同步快照只使用无密钥 SHA-256 摘要，接收端校验内容完整性、设备 ID、代次和 revision，但没有 HMAC、设备签名或可信设备注册。远端偏好可以更新翻译 Endpoint，而合并逻辑会保留本机 API Key。目录选择还允许普通或共享目录，并不强制 iCloud 私有目录。

**影响**

任何具有同步目录写权限的参与者或进程都可以重新计算摘要、伪造更高字段时钟，把 Endpoint 改为攻击者控制的 HTTPS 服务。用户下一次翻译时，本机 API Key 和待翻译文本会随请求发往该服务。相同信任缺口还能伪造 reset、设备移除、tombstone 和剪贴板对象。

**建议**

- 为同步根建立不存放在同步目录中的认证密钥，对协议、manifest、快照、reset、设备移除标记和凭据副本统一认证；或采用设备公私钥、显式注册和撤销。
- Endpoint 不应由远端静默改变；限制为官方 DashScope HTTPS 主机，或要求本机确认目标变更。
- 对共享目录和非 iCloud 目录阻止启用，或给出足够明确的高风险提示。
- 为伪造高时钟、伪造 Endpoint、非法设备和认证失败增加对抗测试。

### REV-P1-02：固定公开材料派生的 AES-GCM 密钥不提供真正机密性

**位置**

- `Sources/MacToolsCore/Settings/CredentialEnvelope.swift:217`
- `Sources/MacToolsCore/Settings/EncryptedCredentialStore.swift:53`
- `Sources/MacToolsCore/Settings/EncryptedCredentialStore.swift:64`
- `Sources/MacToolsCore/UI/TranslationSettingsEditor.swift:66`
- `docs/superpowers/specs/2026-07-25-encrypted-icloud-credential-design.md:28`
- `docs/superpowers/specs/2026-07-25-encrypted-icloud-credential-design.md:77`

**现象 / 原因**

AES-GCM 的封装、随机 nonce、认证头和原子落盘实现本身合理，但对称密钥完全由源码中的固定公开材料派生。该边界在既有设计中已明确定位为“避免明文误读”，不抵御同时获得程序和密文的主体。

**影响**

- 获得代码和凭据副本的主体可以离线解密 API Key。
- 同步目录写入者可以生成可通过认证的任意凭据或删除墓碑。
- 伪造 `Int64.max` 逻辑时钟后，后续 `max(counter) + 1` 会溢出并中断保存路径。
- 设置页“已安全保存”容易让用户高估实际保护级别。

**建议**

优先使用可跨设备同步的系统 Keychain 能力，或由用户口令/恢复密钥派生包装密钥。若必须保持当前免费账号和普通 iCloud Drive 边界，应停止把 API Key 同步到普通目录，明确使用“混淆保存”而非“安全加密”文案，并为逻辑时钟增加上限和显式溢出处理。

### REV-P1-03：宽泛 designated requirement 削弱 TCC 身份边界

**位置**

- `scripts/package_app.sh:94`
- `scripts/package_app.sh:100`

**现象 / 原因**

可信签名主动指定 `identifier "$BUNDLE_ID" and anchor trusted`；ad-hoc 分支只指定 `identifier "$BUNDLE_ID"`。两者都覆盖 `codesign` 默认生成的 designated requirement，并移除了证书叶、Team ID 等更精确的身份约束。

**影响**

另一个使用相同 bundle ID 且满足宽泛 requirement 的构建，可能被 TCC 视为同一代码身份。MacTools 同时申请辅助功能、输入监控、屏幕录制和 Finder Automation，身份误匹配后的权限影响较大。

**建议**

优先使用 `codesign` 默认 requirement。确有跨构建共享 TCC 的需求时，应依据 TN3127 分别为开发和 Developer ID 发布设计包含证书链或 Team ID 的精确规则，并以打包应用验证授权继承、撤销和恶意同 bundle ID 替换场景。

### REV-P1-04：超级右键旧任务可在停用后弹窗或覆盖新内容

**位置**

- `Sources/MacTools/App/SuperRightClickMonitor.swift:73`
- `Sources/MacTools/App/SuperRightClickMonitor.swift:168`
- `Sources/MacTools/App/SuperRightClickMonitor.swift:187`
- `Sources/MacTools/App/AppEnvironment.swift:565`

**现象 / 原因**

长按后的 selection/translation `Task` 没有保存句柄、generation 或 presentation identity。`stop()` 只移除 event tap 和 timer；设置更新替换 monitor 后，旧任务仍能通过原回调展示结果。连续两次长按时，请求也可能乱序完成。

**影响**

- 关闭超级右键后仍可能出现旧面板。
- 较早文本的译文可以覆盖当前选区面板。
- 用户可能复制或朗读与当前上下文不一致的内容。

**建议**

保存 capture/translation task，在新长按、`stop()` 和路由变化时取消。每次请求生成 ID，初始捕获与译文发布前同时检查取消状态、monitor generation 和当前 presentation ID。

### REV-P1-05：授权返回应用后，权限状态和超级右键不会自动恢复

**位置**

- `Sources/MacTools/App/AppDelegate.swift:10`
- `Sources/MacTools/App/RuntimeViews.swift:323`
- `Sources/MacTools/App/RuntimeViews.swift:349`
- `Sources/MacTools/App/AppEnvironment.swift:565`

**现象 / 原因**

权限摘要只在设置视图 `onAppear` 时读取。应用没有在 `applicationDidBecomeActive` 或工作区激活通知中重新检查权限；启动时 event tap 安装失败后，用户在系统设置授权并返回，monitor 也不会重装。

**影响**

首次授权的常见路径中，设置仍显示未授权，超级右键继续不可用，用户只能重启应用或保存会触发 monitor 重建的设置。

**建议**

建立权限运行时协调器，在应用重新激活时重新读取状态；权限从缺失变为满足时重装 monitor，撤销时停止或降级。权限摘要应由可观察状态驱动，并覆盖授权、拒绝、撤销和重新授权测试。

### REV-P1-06：只有屏幕录制权限时，选区覆盖层可能无法用 Esc 退出

**位置**

- `Sources/MacTools/App/ScreenCapture/ScreenSelectionOverlayController.swift:45`
- `Sources/MacTools/App/ScreenCapture/ScreenSelectionOverlayController.swift:71`
- `Sources/MacTools/App/ScreenCapture/ScreenSelectionOverlayController.swift:78`
- `Sources/MacTools/App/ScreenCapture/ScreenSelectionOverlayController.swift:180`

**现象 / 原因**

选区窗口使用 `.nonactivatingPanel`，并明确返回 `canBecomeKey == false`。本地键盘 monitor 无法接收其他应用仍为前台时的 Esc；备用全局键盘 monitor 又依赖 Accessibility 授权。截图功能因此把取消路径隐式依赖到了屏幕录制以外的权限。

**影响**

只使用截图功能、只授予屏幕录制权限的用户从其他应用启动选区后，可能无法按 Esc 退出全屏遮罩，只能完成一次选择或结束进程。

**建议**

让当前显示器的覆盖层按需成为 key window，并由 responder 或 `cancelOperation` 处理 Esc；不要让截图取消依赖全局键盘监听。必须使用打包应用验证“其他应用前台 + 仅屏幕录制权限”的路径。

### REV-P1-07：关闭同步或切换目录不会使当前同步周期失效

**位置**

- `Sources/MacTools/App/Sync/ICloudDriveSyncCoordinator.swift:87`
- `Sources/MacTools/App/Sync/ICloudDriveSyncCoordinator.swift:118`
- `Sources/MacTools/App/Sync/ICloudDriveSyncCoordinator.swift:249`
- `Sources/MacTools/App/Sync/ICloudDriveSyncCoordinator.swift:264`
- `Sources/MacTools/App/Sync/ICloudDriveSyncCoordinator.swift:301`
- `Sources/MacTools/App/Sync/ICloudDriveSyncCoordinator.swift:403`

**现象 / 原因**

`scheduleToken` 只阻止未来的 30 秒定时触发。已经进入 `cycleRunner.run` 的周期不会因 `setEnabled(false)` 或 `setRootURL` 失效，完成后仍会写旧目录、应用远端设置并发布状态。

**影响**

用户关闭同步后，本轮仍可能继续写 iCloud；切换目录后，本轮仍写旧目录；`.off` 或 `.unconfigured` 还可能被旧周期的 `.synced` / `.failed` 覆盖。

**建议**

为每轮同步分配配置 generation/cancellation token。关闭、换目录、重置时立即使旧代际失效；在每个阶段边界、远端写入前和所有 handler 发布前再次校验 generation。

## P2：真实缺陷与必要工程缺口

### 系统集成与正确性

| ID | 位置 | 现象 / 影响 | 建议 |
| --- | --- | --- | --- |
| REV-P2-01 | `Sources/MacTools/App/ScreenCapture/MP4ScreenRecorder.swift:158`、`Sources/MacTools/App/ScreenCapture/ScreenCaptureCoordinator.swift:164` | ScreenCaptureKit 异常停流只记录 `streamFailure`，UI 仍显示“正在录制”，可能让用户误以为内容仍在保存 | 为 recorder 增加单次终止事件；异常停流自动 finalize、关闭控制面板并显示失败 |
| REV-P2-02 | `Sources/MacToolsCore/HotKeys/HotKeyService.swift:25`、`:29`、`:30`、`:207` | 注册错误被 `try?` 吞掉，内部却先记录 binding；系统冲突时设置显示成功但快捷键无效 | 成功后再写 binding，返回逐项错误，并检查 `InstallEventHandler` 状态 |
| REV-P2-03 | `Sources/MacTools/App/SystemWindowLayoutService.swift:49`、`:84`、`:100`、`:132` | AX 写入错误全部丢弃，仍记录成功并推进循环；窗口 ID 依赖私有 `_AXUIElementGetWindow`，失败时共用 ID `0` | 传播 AX 错误并回读 frame；使用公开窗口列表匹配，或取消对私有窗口 ID 的依赖 |
| REV-P2-04 | `Sources/MacTools/App/RuntimeViews.swift:203`、`Sources/MacToolsCore/UI/SettingsView.swift:95`、`:127` | 远端设置到达时，多数设置草稿仍保留初始化值；下一次保存可能把远端新值覆盖回旧值 | 为每组设置建立 draft + dirty 合并策略，外部变更只刷新未编辑字段 |
| REV-P2-05 | `Sources/MacTools/App/RuntimeViews.swift:416`、`:419`、`:598`、`:606` | 翻译中仍可修改输入或切换模块；旧任务完成后会回写与当前输入不匹配的结果 | 保存 task/generation，在输入变化和视图消失时取消，提交前核对请求 ID |

### 性能、并发与数据完整性

| ID | 位置 | 现象 / 影响 | 建议 |
| --- | --- | --- | --- |
| REV-P2-06 | `Sources/MacTools/MacToolsMain.swift:8`、`Sources/MacTools/App/AppEnvironment.swift:193`、`Sources/MacToolsCore/Storage/UnifiedStoreBootstrapper.swift:65` | `app.run()` 前同步执行迁移、Store 复制、图片导入、完整性检查和逐文件验证；大历史首次启动可能长时间无 UI | 使用轻量运行时壳先启动主循环，后台 bootstrap 后在 MainActor 原子发布依赖 |
| REV-P2-07 | `Sources/MacTools/App/ClipboardPanelModel.swift:32`、`:45`、`Sources/MacToolsCore/Paste/PasteActionService.swift:31`、`Sources/MacToolsCore/UI/ClipboardRowView.swift:360` | MainActor 同步查询 SQLite、读取/转码图片、执行 GC；SwiftUI `body` 还同步 `stat` 图片路径 | 增加异步存储 facade；读盘、转码、GC 和文件属性查询离开 MainActor |
| REV-P2-08 | `Sources/MacToolsCore/Sync/SyncLocalRepository.swift:427`、`:456`、`Sources/MacToolsCore/Storage/ClipboardRepository.swift:246`、`:452` | 远端图片先落盘、释放锁后再写数据库引用；并发 reconcile/GC 可在窗口期删除该对象 | 增加 remote-import API，在同一 PayloadStore 锁内完成落盘和数据库 upsert |
| REV-P2-09 | `Sources/MacToolsCore/Sync/DriveSyncStore.swift:739`、`Sources/MacToolsCore/Sync/CredentialReplicaStore.swift:136`、`Sources/MacToolsCore/Sync/SyncLocalRepository.swift:423` | 协议、快照、凭据、记录数和字符串没有前置配额；PNG 在完整读入和散列后才检查 64 MiB | 读取前检查元数据大小；限制文件、设备、记录和字段数量；大对象使用流式散列 |
| REV-P2-10 | `Sources/MacTools/App/AppEnvironment.swift:403`、`:416` | 先保存凭据文件，再保存偏好 SQLite；后者失败时界面报失败但凭据已经改变，且无回滚 | 使用跨存储提交意图和启动恢复；至少保留旧 envelope 并在偏好失败时恢复 |

### 隐私、资源与发布

| ID | 位置 | 现象 / 影响 | 建议 |
| --- | --- | --- | --- |
| REV-P2-11 | `Sources/MacTools/App/AppEnvironment.swift:204`、`:256`、`Sources/MacTools/App/AppEnvironment+Credentials.swift:158`、`Sources/MacToolsCore/Storage/UnifiedStoreBootstrapper.swift:17`、`:248` | 内存降级时旧明文凭据不再清理；legacy/rollback Store 没有保留期限，用户清空当前数据后旧副本仍存在 | 将旧凭据清理解耦于 SQLite；为迁移源和 rollback 制定期限，并纳入删除语义 |
| REV-P2-12 | `Sources/MacToolsCore/Utilities/Logger.swift:10`、`:37`、`:61`、`Sources/MacTools/App/ContextPanelController.swift:365`、`Sources/MacTools/App/ScreenCapture/ScreenCaptureCoordinator.swift:185`、`Sources/MacTools/App/AppEnvironment.swift:642`、`Sources/MacTools/App/AppEnvironmentWorkers.swift:142` | 内存消息和 `debug.log` 永久追加；日志记录绝对路径、应用活动和录屏位置 | 改用隐私标注 Unified Logging；使用环形缓冲和轮转，删除绝对路径与应用名 |
| REV-P2-13 | `.github/workflows/release.yml:19`、`:62`、`scripts/package_app.sh:94`、`scripts/create_dmg.sh:47` | GitHub Release 固定发布 ad-hoc DMG，未启用 Hardened Runtime、时间戳、公证或 stapling；发布任务也不运行测试 | 拆分开发与正式发布；正式发布使用 Developer ID、`--options runtime`、时间戳、公证、stapling、`spctl` 和测试门禁 |
| REV-P2-14 | `Package.swift:1`、`Package.resolved` | 包仍是 Swift 5.10 模式；Swift 6 构建被 GRDB `6.29.3` 的并发安全错误阻断，生产源码中的 22 个 `@unchecked Sendable` 继续依赖人工不变量 | 评估迁移 GRDB 7，先固定 Swift 5 complete checking，再逐 target 启用 Swift 6 |

### 测试与可访问性

| ID | 位置 | 现象 / 影响 | 建议 |
| --- | --- | --- | --- |
| REV-P2-15 | `Package.swift:25`、`Tests/MacToolsCoreTests/SuperRightClickMonitorSourceTests.swift`、`Tests/MacToolsCoreTests/RecordingControlPanelSourceTests.swift` | 唯一 test target 只依赖 `MacToolsCore`；App 目标不进入覆盖率，关键集成多为源码字符串断言 | 把权限协调、录制生命周期、热键结果、AX 写入和翻译 generation 抽成确定性行为测试；增加打包应用 UI 冒烟 |
| REV-P2-16 | `Sources/MacToolsCore/Panels/ContextPanelWindowAppearance.swift:4`、`Sources/MacTools/App/ContextPanelController.swift:135`、`Sources/MacToolsCore/UI/ClipboardListView.swift:46` | 非激活上下文面板缺少常规 Tab/Return 焦点路径；剪贴板主行用 `onTapGesture`，缺少标准按钮 trait/default action | 为 panel 建立按需 key 策略；行改为 Button 或补齐 VoiceOver label/value/default/custom actions |

## P3：非阻断维护项

| ID | 位置 | 现象 | 建议 |
| --- | --- | --- | --- |
| REV-P3-01 | `.github/workflows/release.yml:1`、`Package.swift:25` | 仓库没有 PR/分支测试工作流、格式化或 lint 配置；现有 workflow 只在 tag 上发布 | 增加 `swift test`、Swift 5 complete concurrency、`git diff --check` 和敏感字段扫描门禁 |
| REV-P3-02 | `Sources/MacToolsCore` | 暴露 228 个 public 类型声明，但没有统一 DocC/API 文档门禁 | 按 Swift API Design Guidelines，为跨模块 public API 补充用途、不变量、线程模型和复杂度说明 |
| REV-P3-03 | `Sources/MacToolsCore/Storage/ClipboardRepository.swift`、`Sources/MacTools/App/AppEnvironment.swift`、`Sources/MacTools/App/RuntimeViews.swift`、`Sources/MacToolsCore/Sync/DriveSyncStore.swift`、`Sources/MacToolsCore/Sync/SyncLocalRepository.swift` | 上述核心文件均超过 750 行 | 按事务边界和状态所有权继续拆分，优先处理本报告涉及的同步代际、存储 actor 和运行时协调器 |

## 已确认良好的实现

### 数据与安全控制

- 本地数据库、Payload 和凭据目录使用 `0700`，敏感文件使用 `0600`。
- 凭据文件使用 staging、原子 rename、回读验证和 AES-GCM 认证；缺口是密钥材料公开，不是算法调用错误。
- API Key 不进入 SQLite 普通设置、普通同步快照或剪贴板对象。
- Payload 与同步对象使用 SHA-256 内容寻址，并校验受限相对路径，未发现直接路径穿越。
- SQLite 写操作普遍通过 GRDB writer 事务执行，统一迁移包含 staging、完整性和外键检查。

### 生命周期与并发控制

- `FinderFolderResolutionCoordinator` 同时使用 task cancel 和 generation，能抑制过期 Finder 结果。
- Finder AppleScript runner 具备取消处理、进程终止和回收路径。
- `ScreenCapturePreparationCache` 复用单一准备任务，invalidate 时取消并递增 generation。
- `TranslationSpeechController` 使用 playback generation，旧朗读 completion 不会覆盖新状态。
- panel monitor、观察者、选区 monitor、粘贴激活观察者和录屏 timer 均有明确移除路径。
- 图片预览 decode 已在 detached task 中执行，`NSCache` 有 120 项和 128 MB 上限。

### 测试基础

- 416 个测试全部通过，数据库、迁移、同步收敛、凭据封装、剪贴板和 Core 状态机覆盖较完整。
- `MacToolsCore` 非 UI 文件行覆盖率约 84.34%。
- Swift 5 模式启用 complete concurrency checking 后无编译警告。

## 覆盖率与测试解释

| 指标 | 结果 | 解读 |
| --- | ---: | --- |
| XCTest | 416 / 416 通过 | Core 回归基础较好 |
| `MacToolsCore` 总行覆盖率 | 54.97% | 被大量 SwiftUI view body 的 0%–26% 覆盖拉低 |
| `MacToolsCore` 排除 `UI/` 后行覆盖率 | 84.34% | 存储、同步和状态逻辑覆盖较强 |
| `MacTools` App 目标 | 不在覆盖率产物中 | AppKit、权限、event tap、录制 delegate 和运行时装配仍是主要盲区 |
| 源码结构断言 | 14 个测试文件直接读取仓库源码或脚本 | 可防止约定漂移，但不能替代行为测试 |

测试通过不能否定本报告中的系统集成问题：其中多项需要应用激活、真实 TCC、全局事件、异常停流、文件提供器延迟或并发时序才能触发。

## 已接受但仍需显式管理的风险

| 当前边界 | 原因 / 影响 |
| --- | --- |
| 固定公开材料派生凭据密钥 | 支持 ad-hoc 重建和跨设备直接恢复，但只能防误读，不能抵御有代码和密文的主体 |
| 普通 iCloud Drive 同步文字和图片不做应用层加密 | 数据保护依赖 iCloud 账号、系统权限和用户是否启用 Advanced Data Protection |
| ad-hoc GitHub Release | workflow 已披露仅建议可信小范围开发使用，但不应被视为普通用户正式发行物 |
| 不启用 App Sandbox | 辅助功能、全局事件、Finder 和文件选择能力使沙箱策略更复杂；更需要精确签名、最小权限和可信发布链补偿 |

接受风险不等于关闭问题。REV-P1-01 的“远端设置改变凭据发送目标”不属于上述边界，应单独修复。

## 官方规范与检查依据

### Swift、并发与性能

- [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)：public API 清晰度、命名和文档。
- [Enable data-race safety checking](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/enabledataracesafety/)：Swift 6 language mode 和 complete checking。
- [SE-0304 Structured Concurrency](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md)：任务所有权、合作式取消和结构化生命周期。
- [Apple MainActor](https://developer.apple.com/documentation/swift/mainactor)：UI 隔离和主执行器边界。
- [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)：非 UI 工作离开主线程。
- [Improving performance and stability when accessing the file system](https://developer.apple.com/documentation/foundation/improving-performance-and-stability-when-accessing-the-file-system)：避免主线程即时文件 I/O，尤其是 File Provider、网络盘和外置设备。

### macOS 集成、可访问性与发行

- [NSEvent global monitor](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents%28matching%3Ahandler%3A%29)：全局键盘监听的 Accessibility 条件。
- [NSWindow.canBecomeKey](https://developer.apple.com/documentation/appkit/nswindow/canbecomekey)：键盘 responder 和 key window 条件。
- [SCStreamDelegate.didStopWithError](https://developer.apple.com/documentation/screencapturekit/scstreamdelegate/stream%28_%3Adidstopwitherror%3A%29)：采集流异常终止通知。
- [AXUIElementSetAttributeValue](https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue)：AX 写入错误处理。
- [Accessibility HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility)：键盘和辅助技术可操作性。
- [TN3127: Inside Code Signing Requirements](https://developer.apple.com/documentation/Technotes/tn3127-inside-code-signing-requirements)：designated requirement 身份边界。
- [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)：macOS 运行时保护和公证前提。
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)：Developer ID、时间戳、公证和 stapling。

### 安全、密码与数据生命周期

- [Apple Keychain Services](https://developer.apple.com/documentation/security/keychain-services)：小型秘密的系统安全存储。
- [Apple kSecAttrSynchronizable](https://developer.apple.com/documentation/security/ksecattrsynchronizable)：同步 Keychain 项的系统能力与属性边界。
- [Apple App Transport Security](https://developer.apple.com/documentation/security/preventing-insecure-network-connections)：默认安全网络传输。
- [Apple iCloud security overview](https://support.apple.com/guide/security/icloud-security-overview-secacde2d0da/web)：iCloud 数据保护与 Advanced Data Protection 边界。
- [NIST SP 800-57 Part 1 Rev.5](https://csrc.nist.gov/pubs/sp/800/57/pt1/r5/final)：对称密钥保密和生命周期。
- [OWASP Cryptographic Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html)：密钥独立存储、随机性和敏感数据最小化。
- [OWASP Key Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Key_Management_Cheat_Sheet.html)：密钥、HMAC/签名和未授权实体隔离。
- [CWE-345](https://cwe.mitre.org/data/definitions/345.html)、[CWE-770](https://cwe.mitre.org/data/definitions/770.html)、[CWE-532](https://cwe.mitre.org/data/definitions/532.html)、[CWE-459](https://cwe.mitre.org/data/definitions/459.html)、[CWE-922](https://cwe.mitre.org/data/definitions/922.html)：来源真实性、资源配额、日志隐私、残留数据清理和敏感信息存储。
- [GRDB 官方发布](https://github.com/groue/GRDB.swift/releases)：当前 Swift 6 兼容版本和迁移基线。

## 验证证据

| 命令 | 结果 |
| --- | --- |
| `swift test` | 416 项通过，0 失败 |
| `swift test --enable-code-coverage` | 416 项通过；生成覆盖率数据 |
| `swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warn-concurrency` | 通过，无警告 |
| `swift build -Xswiftc -swift-version -Xswiftc 6` | 失败；GRDB `6.29.3` 首先出现并发安全编译错误 |
| `scripts/package_app.sh` | 未完成；GRDB `SQLiteCustom/src` 子模块下载先发生 HTTP/2 framing error / connection reset；复验在同一 clone 阶段持续无进展后终止 |

打包未完成发生在外部依赖下载阶段，不是 MacTools 源码编译失败；因此本次没有生成新的签名、Gatekeeper、TCC 或运行时验证证据。

## 未验证边界

- 未读取真实 `debug.log`、SQLite、剪贴板缓存、录屏或用户 iCloud 目录，避免接触本地敏感数据。
- 未改变或读取真实 TCC 授权状态。
- 未执行打包应用下的超级右键、Finder Automation、截图录屏、窗口布局和 VoiceOver 人工冒烟。
- 未执行真实双 Mac iCloud Drive 冲突、恶意副本、断网恢复和大文件资源耗尽测试。
- 未执行 Thread Sanitizer、Instruments hang/内存分析、异常停流注入或文件系统断电测试。
- 未验证 Developer ID、公证、stapling、Gatekeeper 和宽泛 requirement 的实机身份继承。

## 修复顺序

| 阶段 | 目标 | 对应问题 |
| --- | --- | --- |
| 1. 安全止血 | 阻止远端 Endpoint 静默变更；确定凭据同步策略；收紧代码 requirement | P1-01、P1-02、P1-03 |
| 2. 生命周期正确性 | 为超级右键和同步周期增加 generation/cancel；恢复授权监听；修复 Esc | P1-04 至 P1-07 |
| 3. 数据与录制可靠性 | 异常停流、远端图片原子导入、跨存储凭据提交、旧副本生命周期 | P2-01、P2-08 至 P2-11 |
| 4. 响应性与可用性 | 后台启动 bootstrap、剪贴板异步存储、热键/AX 错误反馈、设置 draft | P2-02 至 P2-07 |
| 5. 工程门禁 | Developer ID 发行链、Swift 6/GRDB 迁移、App 行为测试、可访问性审计 | P2-13 至 P3-03 |

完成阶段 1 和阶段 2，并确认没有未解决 P1 后，才适合把审查状态改为“通过”；正式面向普通用户发布前还必须完成 Developer ID、Hardened Runtime、公证及打包应用人工验收。
