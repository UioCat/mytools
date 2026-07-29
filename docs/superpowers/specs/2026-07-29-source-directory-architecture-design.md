# 源码目录架构优化设计

## 状态

- 状态：待评审
- 变更性质：保持行为的源码目录重组

## 背景

当前项目通过 `MacTools` 可执行 Target 和 `MacToolsCore` 库 Target 建立了基本编译边界，但两个
Target 内部的物理目录还不能直接表达文件职责：

- `Sources/MacTools/App` 同时容纳应用入口、依赖装配、功能协调器和系统适配器。
- `Sources/MacToolsCore/UI` 同时容纳工作台、各功能页面、设置编辑器和设计系统组件。
- 部分源码结构测试直接引用旧路径，目录职责发生变化时需要逐个同步。

现有代码已经通过协议注入、Actor 隔离和 `AppEnvironment` 装配保持了运行边界。本方案只让目录结构
与这些真实职责一致，不重新设计业务流程。

## 目标

- `MacTools` 内明确区分应用装配、功能协调和 macOS 系统适配。
- `MacToolsCore/UI` 内按功能聚合页面，并单独识别工作台和设计系统。
- 保持现有 SwiftPM Target、依赖方向、类型名、访问级别和运行时行为不变。
- 使用源码结构测试防止 UI 直接依赖数据库和同步存储实现。
- 更新仍代表当前状态的仓库说明和测试路径，保留历史设计文档中的原始路径。

## 非目标

- 不新增 `MacToolsUI`、`MacToolsData` 或其他 SwiftPM Target。
- 不修改 `Package.swift` 的产品、Target 或依赖。
- 不修改业务逻辑、UI 布局、文案、持久化格式、同步协议、权限流程或系统行为。
- 不重排 `Tests/MacToolsCoreTests`；测试目录镜像化不与生产源码重组同时实施。
- 不批量修改已经完成的历史设计和实施文档。

## 方案选择

| 方案 | 收益 | 成本与风险 | 结论 |
| --- | --- | --- | --- |
| 在现有 Target 内按职责重组 | 立即降低查找成本，不产生新模块接口 | 仍依赖目录和测试守卫边界 | 当前方案 |
| 拆分 `MacToolsUI` 和 `MacToolsData` | 获得编译期依赖边界 | 需要扩大 `public` API，并处理跨 Target 装配 | 当前不采用 |
| 仅重命名 `MacToolsCore` | 名称更贴近共享库 | 不能改善目录职责或依赖边界 | 不采用 |

当前项目只有一个 macOS 客户端，尚未出现跨平台复用或编译性能阻塞。先完成 Target 内重组可以获得
主要可维护性收益，同时保留未来按相同目录边界拆 Target 的迁移路径。

## 目录设计

### `MacTools` 可执行 Target

```text
Sources/MacTools/
├── Application/
│   ├── MacToolsMain.swift
│   ├── AppDelegate.swift
│   ├── AppEnvironment.swift
│   ├── AppEnvironment+Credentials.swift
│   ├── AppEnvironmentWorkers.swift
│   ├── MenuBarController.swift
│   ├── MenuBarLogoImage.swift
│   └── RuntimeViews.swift
├── Features/
│   ├── Clipboard/
│   │   └── ClipboardPanelModel.swift
│   └── SuperRightClick/
│       ├── ContextPanelController.swift
│       └── SuperRightClickMonitor.swift
├── Platform/
│   ├── ScreenCapture/
│   ├── Speech/
│   │   └── SystemTranslationSpeechEngine.swift
│   ├── Sync/
│   │   ├── ICloudDriveSyncCoordinator.swift
│   │   └── KeychainCredentialStore.swift
│   └── WindowLayout/
│       └── SystemWindowLayoutService.swift
└── Resources/
```

目录职责如下：

| 目录 | 职责 | 允许依赖 |
| --- | --- | --- |
| `Application` | 入口、生命周期、依赖装配、菜单栏和运行时 SwiftUI 接线 | `MacToolsCore`、`Features`、`Platform` |
| `Features` | 可执行层特有的功能状态和交互协调 | `MacToolsCore`、所需系统框架 |
| `Platform` | ScreenCaptureKit、辅助功能、语音、iCloud Drive 和旧 Keychain 等系统实现 | `MacToolsCore`、Apple 系统框架 |
| `Resources` | 图标和随应用打包的资源 | 无源码依赖 |

`AppEnvironment` 继续作为唯一主要 composition root。目录移动后不引入新的全局单例，也不把依赖创建
下沉到 View 或 Core 业务服务。

### `MacToolsCore` 库 Target

现有业务目录保持不变：

```text
Clipboard/       FileActions/     HotKeys/          Panels/
Paste/           Permissions/     RightClick/       ScreenCapture/
Settings/        Storage/         Sync/             Translation/
Utilities/       WindowLayout/
```

只重组当前扁平的 `UI` 目录：

```text
Sources/MacToolsCore/UI/
├── DesignSystem/
│   ├── LiquidGlassSurface.swift
│   └── MacToolsGlassTheme.swift
├── Workspace/
│   ├── MainToolModule.swift
│   └── MainWorkspaceView.swift
├── Clipboard/
│   ├── ClipboardListView.swift
│   ├── ClipboardRowView.swift
│   └── MainPanelView.swift
├── Translation/
│   ├── TranslationInputEditorLayout.swift
│   ├── TranslationInputKeyCommand.swift
│   ├── TranslationWorkspaceContent.swift
│   └── TranslationSettingsEditor.swift
├── Settings/
│   ├── ClipboardSettingsEditor.swift
│   ├── PermissionStatusRow.swift
│   ├── SettingsComponents.swift
│   ├── SettingsNavigation.swift
│   ├── SettingsView.swift
│   ├── SyncSettingsEditor.swift
│   ├── WindowLayoutSettingsEditor.swift
│   └── WindowLayoutSettingsPresentation.swift
└── SuperRightClick/
    ├── ContextActionView.swift
    ├── SuperPanelContent.swift
    ├── SuperPanelLayout.swift
    └── SuperPanelPreviewLineLimitPolicy.swift
```

`UI` 仍属于 `MacToolsCore` Target，但必须保持以下源码级边界：

- 可以依赖公开领域模型、服务协议、权限状态和展示策略。
- 不直接导入 `GRDB`。
- 不直接创建或引用 `ClipboardDatabase`、`ClipboardRepository`、`DriveSyncStore`、`PayloadStore`、
  `PreferenceRepository`、`DeviceOverrideRepository` 或 `EncryptedCredentialStore`。
- 数据加载、保存和系统操作继续通过状态对象或闭包从 `Application` 注入。

## 路径与文档迁移

需要更新的当前路径引用包括：

- `Tests/MacToolsCoreTests` 中读取源码文件的结构测试。
- 根目录 `AGENTS.md` 的仓库结构和架构边界。
- `README.md` 中仍代表当前实现的源码路径。

`docs/superpowers/specs`、`docs/superpowers/plans` 和其他已完成设计中的旧路径用于记录当时的实现上下文，
保持原样。脚本中的资源路径不变化。

## 实施约束

- 只移动文件和更新路径引用；生产 Swift 文件正文不做顺手重构。
- 使用 Git 可识别的文件移动，保证评审时能够区分移动与内容修改。
- 新增结构测试时只检查稳定的依赖边界，不锁定容易变化的完整文件清单。
- SwiftPM 会递归收集 Target 目录内的 Swift 文件，因此目录移动不需要修改 `Package.swift`。
- 如果移动暴露出依赖顺序或访问级别问题，优先调整目录方案，不扩大公开 API。

## 风险与处理

| 风险 | 处理 |
| --- | --- |
| 源码测试仍读取旧路径 | 全仓扫描当前源码和测试引用，并运行相关聚焦测试 |
| 可执行 Target 未被测试 Target 编译 | 单独构建 `MacTools` 产品，并执行应用打包 |
| 大量移动掩盖意外正文修改 | 检查 `git diff --summary`、`git diff --stat` 和非重命名差异 |
| UI 继续越过边界访问存储 | 增加递归源码边界测试，禁止 GRDB 和具体存储类型 |
| 历史文档被无意义改写 | 只更新 `AGENTS.md`、`README.md` 和当前测试 |

## 验证

按以下顺序验证：

1. 运行 `CodeOrganizationSourceTests` 及所有依赖固定源码路径的聚焦测试。
2. 运行 `swift test`，验证 `MacToolsCore` 和完整测试套件。
3. 运行 `swift build --product MacTools`，验证可执行 Target。
4. 运行 `scripts/package_app.sh`，验证资源收集、发布构建和签名装配。
5. 运行 `git diff --check`，并核对文件移动范围。
6. 扫描受版本控制的源码和文档，确认没有新增真实凭据或用户路径。

本次不改变 UI 输出和运行时行为，因此不要求新增 UI 截图基线；如果实施中出现任何生产 Swift 正文变化，
则按对应功能补充聚焦测试和人工验证。

## 验收标准

- `MacTools` 的入口、功能协调器和系统适配器可以仅通过目录识别。
- `MacToolsCore/UI` 可以按工作台、功能页面和设计系统定位文件。
- `Package.swift` 和所有生产 Swift 文件行为保持不变。
- UI 存储依赖守卫通过，所有测试、可执行构建和打包命令成功。
- 当前说明文档不再把系统集成统一描述为旧的 `Sources/MacTools/App` 路径。
