# MacTools 生产源码中文注释 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `Sources/` 下全部 105 个生产 Swift 文件建立中文文件、类型、方法和核心逻辑注释基线，且不改变任何可执行行为。

**Architecture:** 先用只插入注释的机械转换建立全覆盖基线，再按模块人工复核和改写低信息量注释，最后使用 diff 守卫证明所有源码变化都仅为注释或空行。核心同步、存储、凭据、权限和 AppKit 集成按调用链补充不变量与副作用说明。

**Tech Stack:** Swift 5.10、SwiftPM、AppKit、SwiftUI、GRDB、Ruby 静态转换、Git diff 守卫。

## Global Constraints

- 只修改 `Sources/` 下 105 个生产 Swift 文件中的注释和必要空行。
- `Tests/`、依赖、生成物、资源和运行时数据不在修改范围内。
- 每个文件、具名类型、`func`、`init`、`deinit`、`subscript`、重写方法和协议实现均需中文说明。
- 闭包和简单计算属性不强制独立注释；承担状态转换、资源释放或线程切换时必须说明。
- 不通过注释掩盖 `REVIEW.md` 中的已知风险，不把未实现的保护写成当前不变量。
- 每批改动后检查非注释源码没有变化，最终运行完整测试与并发检查。

---

### Task 1: 建立机械注释基线

**Files:**
- Modify: `Sources/**/*.swift`
- Temporary create/delete: `scripts/.add_chinese_source_comments.rb`

**Interfaces:**
- Consumes: `docs/superpowers/specs/2026-07-26-source-chinese-comment-design.md`
- Produces: 每个生产 Swift 文件的文件级中文说明，以及每个目标类型和方法前的中文 `///` 基线注释。

- [ ] **Step 1: 记录修改前范围**

Run:

```bash
git status --short
rg --files Sources -g '*.swift' | sort
rg --files Sources -g '*.swift' | wc -l
```

Expected: 工作树只包含本任务计划文件；生产 Swift 文件数为 105。

- [ ] **Step 2: 创建一次性转换器**

转换器必须：

```text
1. 只遍历 Sources/**/*.swift。
2. 根据目录职责在 import 前插入两行中文文件说明。
3. 为 class/struct/enum/actor/protocol/extension/typealias 插入中文文档注释。
4. 为 func/init/deinit/subscript 插入中文文档注释。
5. 已有 /// 时不重复插入。
6. 处理声明前的 @MainActor、@objc、@discardableResult 等属性。
7. 不重写任何非注释行。
```

- [ ] **Step 3: 运行转换并立即删除一次性转换器**

Run:

```bash
ruby scripts/.add_chinese_source_comments.rb
```

转换完成后删除 `scripts/.add_chinese_source_comments.rb`，最终提交中不得包含转换器。

- [ ] **Step 4: 检查所有变更均为注释**

Run:

```bash
git diff -U0 -- Sources
```

逐个检查新增或删除行；除空行外，所有变化必须以 `//` 开始。出现 import、声明、表达式或字符串
变化时立即恢复该行并修正转换器。

### Task 2: 复核 Core 领域与系统服务

**Files:**
- Modify: `Sources/MacToolsCore/Clipboard/*.swift`
- Modify: `Sources/MacToolsCore/FileActions/*.swift`
- Modify: `Sources/MacToolsCore/HotKeys/*.swift`
- Modify: `Sources/MacToolsCore/Panels/*.swift`
- Modify: `Sources/MacToolsCore/Paste/*.swift`
- Modify: `Sources/MacToolsCore/Permissions/*.swift`
- Modify: `Sources/MacToolsCore/RightClick/*.swift`
- Modify: `Sources/MacToolsCore/ScreenCapture/*.swift`
- Modify: `Sources/MacToolsCore/Translation/*.swift`
- Modify: `Sources/MacToolsCore/Utilities/*.swift`
- Modify: `Sources/MacToolsCore/WindowLayout/*.swift`

**Interfaces:**
- Consumes: Task 1 的机械注释基线。
- Produces: 能解释领域目的、系统副作用、状态机转换、取消条件和错误语义的中文注释。

- [ ] **Step 1: 逐文件读取完整类型和调用方**

使用 `rg` 定位每个公开类型的调用方，核对注释中的状态所有权、线程边界和返回值语义。

- [ ] **Step 2: 改写低信息量方法注释**

将“执行某方法对应操作”改成可验证的业务说明。例如：

```swift
/// 根据按下、定时器触发和抬起事件推进长按状态机，并返回是否需要抑制系统右键。
func handle(_ event: RightClickEvent) -> RightClickRoute
```

- [ ] **Step 3: 补充核心代码块说明**

重点说明 Finder 取消与 generation、右键短按回放、截图 preparation 复用、热键注册、自动粘贴权限和
朗读 completion 防过期机制。

- [ ] **Step 4: 运行 Core 构建**

Run:

```bash
swift build --target MacToolsCore
```

Expected: exit 0。

### Task 3: 复核设置、存储、同步与凭据

**Files:**
- Modify: `Sources/MacToolsCore/Settings/*.swift`
- Modify: `Sources/MacToolsCore/Storage/*.swift`
- Modify: `Sources/MacToolsCore/Sync/*.swift`

**Interfaces:**
- Consumes: 现有 GRDB、PayloadStore、同步协议和凭据信封实现。
- Produces: 能准确说明事务、逻辑时钟、摘要、staging、回滚、AAD 和冲突胜负的中文注释。

- [ ] **Step 1: 按调用链复核方法注释**

顺序为 `AppSettings` → repository/store → migration/bootstrap → local sync repository →
drive store/cycle runner → credential replica/reconciler。

- [ ] **Step 2: 补充事务和文件生命周期注释**

必须解释：

```text
GRDB writer 事务边界；
payload 内容寻址与 GC 顺序；
staging、原子 rename 和回读验证；
legacy/rollback 保留语义；
远端对象导入与数据库引用的当前顺序。
```

- [ ] **Step 3: 补充同步和凭据安全边界**

明确 SHA-256 摘要不提供来源认证、固定公开材料不提供真正机密性，以及逻辑时钟和 tombstone
当前实现的胜负规则；不得写成已具备 HMAC、设备签名或秘密密钥。

- [ ] **Step 4: 运行聚焦测试**

Run:

```bash
swift test --filter DriveSync
swift test --filter Credential
swift test --filter UnifiedStoreBootstrapper
swift test --filter ClipboardRepository
```

Expected: 所有筛选测试 0 失败。

### Task 4: 复核 SwiftUI 展示层

**Files:**
- Modify: `Sources/MacToolsCore/UI/*.swift`

**Interfaces:**
- Consumes: Core 模型、编辑器状态和面板展示模型。
- Produces: 能解释草稿状态、焦点、列表选择、异步预览和操作回调的中文注释。

- [ ] **Step 1: 复核 View 与辅助类型**

文件和类型注释必须区分“展示状态”和“持久化状态”，不得把 SwiftUI View 描述成存储所有者。

- [ ] **Step 2: 复核方法与关键计算属性**

所有方法使用 `///`；承担选择、滚动、图像解码、快捷键解释或设置规范化的计算属性和闭包增加
必要 `//` 说明。

- [ ] **Step 3: 翻译既有英文注释**

将 `ClipboardListView` 等文件中准确但为英文的布局和取消说明翻译成中文，保留技术含义。

- [ ] **Step 4: 运行 UI 决策测试**

Run:

```bash
swift test --filter ClipboardListViewTests
swift test --filter TranslationWorkspaceContentTests
swift test --filter WindowLayoutSettingsPresentationTests
```

Expected: 所有筛选测试 0 失败。

### Task 5: 复核 AppKit 与系统集成

**Files:**
- Modify: `Sources/MacTools/MacToolsMain.swift`
- Modify: `Sources/MacTools/App/*.swift`
- Modify: `Sources/MacTools/App/ScreenCapture/*.swift`
- Modify: `Sources/MacTools/App/Sync/*.swift`

**Interfaces:**
- Consumes: `MacToolsCore` 服务和 macOS 框架。
- Produces: 能解释应用生命周期、Main Actor、TCC、事件监听、Finder、录屏和窗口行为的中文注释。

- [ ] **Step 1: 按运行时启动顺序复核**

顺序为 `MacToolsMain` → `AppDelegate` → `AppEnvironment`/workers → menu/panel → 系统服务。

- [ ] **Step 2: 补充系统能力边界**

重点说明 event tap、Carbon hot key、Accessibility、Finder Automation、ScreenCaptureKit delegate、
非激活 panel、全局 monitor 和安全作用域 bookmark 的调用条件及副作用。

- [ ] **Step 3: 翻译既有英文并核对已知风险**

把 `SuperRightClickMonitor`、`MP4ScreenRecorder`、`SystemScreenCaptureService` 的英文并发说明翻译为
中文。注释必须忠实描述当前任务未取消、权限不自动刷新和异常停流处理等现状。

- [ ] **Step 4: 运行 App 源码约定测试**

Run:

```bash
swift test --filter AppEnvironmentStartupSourceTests
swift test --filter SuperRightClickMonitorSourceTests
swift test --filter RecordingControlPanelSourceTests
```

Expected: 所有筛选测试 0 失败。

### Task 6: 全量覆盖审计

**Files:**
- Review: `Sources/**/*.swift`

**Interfaces:**
- Consumes: Tasks 1–5 的全部注释。
- Produces: 文件、类型和方法零遗漏清单，以及仅注释变化的 diff 证据。

- [ ] **Step 1: 检查文件级覆盖**

Run:

```bash
for file in $(rg --files Sources -g '*.swift'); do
  sed -n '1,8p' "$file" | rg -q '^//' || echo "缺少文件注释: $file"
done
```

Expected: 无输出。

- [ ] **Step 2: 检查类型和方法覆盖**

使用声明扫描器列出前方没有 `///` 的 `class`、`struct`、`enum`、`actor`、`protocol`、`extension`、
`typealias`、`func`、`init`、`deinit` 和 `subscript`。逐项判断属性、多行声明和条件编译边界，
直到清单为空。

- [ ] **Step 3: 检查只改注释**

解析 `git diff -U0 -- Sources`。任何新增或删除的非空行若不以 `//` 开始，均视为阻断问题。

- [ ] **Step 4: 抽查核心文件**

至少完整复核：

```text
Sources/MacTools/App/AppEnvironment.swift
Sources/MacTools/App/SuperRightClickMonitor.swift
Sources/MacTools/App/Sync/ICloudDriveSyncCoordinator.swift
Sources/MacToolsCore/Storage/ClipboardRepository.swift
Sources/MacToolsCore/Storage/UnifiedStoreBootstrapper.swift
Sources/MacToolsCore/Sync/DriveSyncStore.swift
Sources/MacToolsCore/Sync/SyncLocalRepository.swift
Sources/MacToolsCore/Settings/CredentialEnvelope.swift
Sources/MacToolsCore/UI/ClipboardListView.swift
```

### Task 7: 最终验证、提交与推送

**Files:**
- Verify: `Sources/**/*.swift`
- Verify: `docs/superpowers/specs/2026-07-26-source-chinese-comment-design.md`
- Verify: `docs/superpowers/plans/2026-07-26-source-chinese-comments.md`

**Interfaces:**
- Consumes: 全部注释改动。
- Produces: 测试、并发构建、敏感扫描、提交范围和远端分支证据。

- [ ] **Step 1: 运行完整验证**

Run:

```bash
swift test
swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warn-concurrency
git diff --check
```

Expected: 416 项测试 0 失败；构建 exit 0 且无并发警告；diff 检查无输出。

- [ ] **Step 2: 扫描敏感字段**

Run:

```bash
rg -n --hidden \
  --glob '!.git/**' \
  --glob '!.worktrees/**' \
  --glob '!.build/**' \
  --glob '!build/**' \
  --glob '!log/**' \
  -i 'api[_ -]?key|access[_ -]?key|secret|token|password|credential|private[_ -]?key|client[_ -]?secret|app[_ -]?secret|authorization|bearer|cookie|session'
```

根据上下文确认匹配仅为字段名、设计说明或测试占位值。

- [ ] **Step 3: 核对并提交范围**

只暂存 `Sources/**/*.swift` 和本实施计划；不得夹带无关用户改动。提交标题和正文使用中文，并记录
覆盖文件数、注释策略和验证结果。

- [ ] **Step 4: 推送并复核远端**

Run:

```bash
git push origin main
git status -sb
git rev-parse HEAD
git ls-remote origin refs/heads/main
```

Expected: 工作树干净，本地与 `origin/main` 哈希一致。
