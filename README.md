# MacTools

MacTools 是一个原生 macOS 菜单栏效率工具，目标是做一个轻量、常驻、可扩展的本地工具箱。它当前围绕剪贴板历史、快捷键主面板、超级右键、文件快捷操作、翻译和权限检查来构建，整体体验参考 uTools，但实现上优先保证原生 macOS 稳定性和可调试性。

## 核心能力

### 菜单栏常驻

- 以菜单栏应用方式运行，默认不显示 Dock 图标。
- 通过全局快捷键打开主面板。
- 默认快捷键：
  - `Option + Space`：打开设置/主面板。
  - `Option + 1`：打开剪贴板历史。
  - `Option + 2`、`Option + 3`：预留工具位。

### 剪贴板历史

- 监听系统剪贴板变化并记录历史。
- 支持内容类型：
  - 文本。
  - URL 文本。
  - 文件。
  - 文件夹。
  - 图片文件。
  - 直接复制的图片数据。
- 支持搜索、收藏、置顶、复制、复制并自动粘贴。
- 元数据使用 SQLite 保存，图片等较大内容缓存到用户 Application Support 目录。

### 超级右键

- 短按右键保留系统默认菜单。
- 长按右键触发 MacTools 超级右键流程。
- 文本场景：
  - 捕获选中文本。
  - 展示类似 uTools 超级面板的浮层。
  - 显示原文、译文或翻译未配置提示。
  - 支持复制译文、文本中转、百度搜索、Bing 搜索等动作。
- 文件/文件夹场景：
  - 复制当前路径。
  - 新建文件。
  - 终端中打开。
  - 在访达中显示。
  - 尝试通过外部应用打开，例如 Claude Code。

### 翻译

- 翻译能力通过 `TranslationProvider` 协议抽象。
- 当前实现接入阿里云百炼 OpenAI 兼容接口，默认模型为 `qwen-mt-turbo`。
- 未配置 API Key 时，超级右键文本面板会给出提示，不会用阻塞弹窗打断操作。

### 权限与诊断

- 权限检查覆盖：
  - 辅助功能，用于全局事件和选区捕获。
  - 输入监控，用于右键事件监听。
  - 自动粘贴相关键盘事件权限。
- 设置页会展示权限状态并提供跳转系统设置的入口。
- `scripts/diagnose_super_right_click.sh` 可检查超级右键的签名、权限、运行进程和日志。

## 设计说明

项目使用 Swift Package Manager 管理，分为可执行应用和核心库两个 target：

- `MacTools`：AppKit 应用入口、菜单栏控制、窗口/面板控制、全局事件监听和运行时装配。
- `MacToolsCore`：剪贴板、存储、快捷键、权限、右键状态机、文件动作、翻译、SwiftUI 视图和可测试业务逻辑。

整体设计原则：

- SwiftUI 负责主要界面：主面板、设置、剪贴板列表、超级右键浮层。
- AppKit 负责系统集成：菜单栏、全局热键、`NSPanel`、剪贴板、系统权限、事件监听。
- 核心逻辑放在 `MacToolsCore`，尽量通过协议注入系统服务，方便单元测试。
- 超级右键按可观测链路拆分：事件触发、权限预检、选区捕获、内容分类、动作匹配、浮层展示。
- 本地用户数据不进入仓库。剪贴板数据库、缓存文件、设置和密钥都应视为敏感本地数据。

## 目录结构

```text
.
├── Package.swift
├── Sources
│   ├── MacTools
│   │   └── App
│   └── MacToolsCore
│       ├── Clipboard
│       ├── FileActions
│       ├── HotKeys
│       ├── Panels
│       ├── Paste
│       ├── Permissions
│       ├── RightClick
│       ├── Settings
│       ├── Storage
│       ├── Translation
│       ├── UI
│       └── Utilities
├── Tests
│   └── MacToolsCoreTests
├── docs
└── scripts
```

## 环境要求

- macOS 13 或更高版本。
- Xcode 或 Xcode Command Line Tools。
- Swift 5.10。

检查 Swift 版本：

```sh
swift --version
```

## 如何运行

### 运行测试

```sh
swift test
```

### 开发模式启动

```sh
swift run MacTools
```

启动后：

1. 菜单栏会出现 MacTools 图标。
2. 使用 `Option + Space` 打开主面板。
3. 使用 `Option + 1` 打开剪贴板历史。

### 构建本地 App Bundle

```sh
scripts/package_app.sh
```

构建完成后启动：

```sh
open build/MacTools.app
```

`package_app.sh` 会优先使用 `MACOS_CODESIGN_IDENTITY` 指定的签名身份；如果没有指定，会尝试使用钥匙串里的 Apple/Developer 代码签名身份。没有可用身份时会退回 ad-hoc 签名，但超级右键相关 TCC 权限可能不稳定。

指定签名身份示例：

```sh
MACOS_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/package_app.sh
```

## 权限配置

超级右键和自动粘贴依赖 macOS 隐私权限。首次运行或更换签名身份后，可能需要重新授权。

建议在系统设置中确认：

- 隐私与安全性 > 辅助功能：允许 `MacTools.app`。
- 隐私与安全性 > 输入监控：允许 `MacTools.app`。

如果授权状态异常，可以重置后重新授权：

```sh
tccutil reset Accessibility local.mactools.mvp
tccutil reset ListenEvent local.mactools.mvp
scripts/package_app.sh
open build/MacTools.app
```

## 超级右键排障

运行诊断脚本：

```sh
scripts/diagnose_super_right_click.sh
```

清理日志并发送一次合成右键探测：

```sh
scripts/diagnose_super_right_click.sh --clear-log --probe
```

排查思路：

- 没有 `right mouse down`：事件监听层失败，优先检查输入监控和签名。
- 有 `long press triggered`，但捕获为空：选区捕获失败，优先检查辅助功能权限和目标应用是否支持选区读取/复制。
- 捕获到了内容但没有动作：内容分类或动作匹配有问题。
- 有动作但没有 UI：浮层展示层有问题。

更多细节见 [docs/super-right-click-debuggable-design.md](docs/super-right-click-debuggable-design.md)。

## 手动验收

常用手动检查清单见 [docs/manual-verification.md](docs/manual-verification.md)。

建议至少验证：

- `Option + Space` 能打开主面板。
- `Option + 1` 能打开剪贴板历史。
- 复制文本、文件、文件夹、图片后，历史列表能出现对应记录。
- 剪贴板条目可以复制或复制并粘贴。
- 短按右键仍显示系统菜单。
- 长按选中文本、文件夹或文件时出现超级右键浮层。
- 翻译未配置时，文本浮层显示提示而不是卡死或弹阻塞窗口。

## 开发约定

- 优先把可测试逻辑放入 `MacToolsCore`。
- AppKit 系统集成放在 `Sources/MacTools/App`。
- 新增行为尽量补充 `Tests/MacToolsCoreTests`。
- 不提交本地凭证、剪贴板缓存、数据库、`.env*`、`.idea/`、`build/` 等本地文件。
- 涉及权限、签名、超级右键时，除了单元测试，也要做实际运行验证。
