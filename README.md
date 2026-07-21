# MacTools

MacTools 是一个基于 SwiftPM 的原生 macOS 菜单栏效率工具。应用以常驻菜单栏的方式提供剪贴板历史、翻译、超级右键、截图与录屏、窗口布局和文件快捷操作；界面使用 SwiftUI，系统集成由 AppKit、Accessibility、Carbon Hot Key 和 ScreenCaptureKit 完成。

## 当前能力

| 模块 | 当前实现 |
| --- | --- |
| 剪贴板 | 记录文本、URL、文件、文件夹和图片；支持搜索、分类、收藏、删除、清空未收藏记录、复制和复制后自动粘贴 |
| 翻译 | 接入阿里云百炼 OpenAI 兼容接口，默认模型为 `qwen-mt-turbo`；中文自动译为英文，其他语言自动译为中文 |
| 超级右键 | 短按保留系统右键菜单；长按根据选中文本、Finder 项目或当前目录展示翻译、文本中转、路径和窗口布局动作 |
| 截图与录屏 | 顶部切换截图或录屏并框选单个显示器内的区域；截图支持线条、画笔、箭头、长方形、预置颜色、线宽和马赛克标注后复制 PNG；录屏输出 H.264 MP4 |
| 窗口布局 | 支持左/右半屏、左/右 1/3、左/右 2/3、居中和满屏，可控制面板入口及各模式快捷键 |
| 设置与权限 | 管理外观、快捷键、统一存储、iCloud Drive 文件夹同步、超级右键响应速度、百炼配置、窗口布局和系统权限状态 |

### 默认快捷键

工具快捷键可在设置中修改。

| 快捷键 | 动作 |
| --- | --- |
| `Option + Space` | 打开主面板的设置页 |
| `Option + 1` | 打开剪贴板历史 |
| `Option + 2` | 打开翻译工具 |
| `Option + 3` | 启动截图与录屏框选 |

窗口布局也有默认快捷键：半屏使用 `Control + Command + ←/→`，1/3 使用 `Control + Option + ←/→`，2/3 使用 `Option + Command + ←/→`，居中和满屏分别使用 `Control + Option + 0`、`Control + Command + 0`。

### 剪贴板历史

- 应用每 `0.75` 秒轮询一次系统剪贴板；普通历史固定保留 `500` 条，新增时按最后捕获或使用时间懒淘汰，收藏和置顶不参与自动淘汰。
- `全部 / 文本 / 图像 / 收藏` 四个分类支持鼠标和键盘切换。
- 剪贴板元数据、普通配置和同步状态统一保存在 `Store/mactools.sqlite3`；直接复制的原始图片进入 `Store/Payloads/` 内容寻址对象库。
- 图片按 SHA-256 去重；记录删除或淘汰后，无引用原图由可重试 GC 自动回收。存储位置和容量不提供自定义入口。
- 收藏记录不会被“清空未收藏记录”删除。

### iCloud Drive 同步

- 在“设置 → 数据与同步”选择一个 iCloud Drive 普通文件夹；该方案不使用 CloudKit、应用专属 iCloud Container、APNs 或 Provisioning Profile，免费开发者账号和 ad-hoc 签名包也可使用。
- 本地 SQLite 始终是运行时数据源，不会同步 `mactools.sqlite3`、`-wal`、`-shm` 或本地 Payload 目录。每台 Mac 只写自己的紧凑快照，共享文字和图片按 SHA-256 内容寻址去重。
- 同步范围包含文字、URL、直接复制的原始图片、收藏/置顶状态和普通配置；Finder 文件路径不跨设备同步，百炼 API Key 只保留在每台 Mac 的本机 Keychain。
- 云端普通历史全局最多 500 条；默认同步目录预算为 512 MiB，可选 256 MiB、512 MiB、1 GiB 或 2 GiB。单张图片最大 64 MiB，收藏和置顶不会被容量策略自动删除。
- 无引用共享对象经过 24 小时稳定观察且所有可见设备快照可验证后才会回收；目录或文件尚未下载时暂停回收，不影响本地剪贴板使用。
- 单个本地图片缺失或单个远端内容对象损坏时会隔离该记录，文字、配置和删除操作仍继续同步；持有正确本地内容的设备可按同一 SHA-256 原子修复损坏对象。
- 设置页列出当前可见设备；移除长期离线设备后，它不再阻塞墓碑压缩和对象回收，若重新上线会自动换用新的设备身份。

### 超级右键与文件动作

长按右键的默认阈值为 `250 ms`，可在 `250 / 300 / 350 ms` 之间调整。当前动作按场景区分：

| 场景 | 动作 |
| --- | --- |
| 选中文本 | 查看自动翻译状态或译文、复制译文、打开文本悬浮中转 |
| Finder 已选文件或文件夹 | 复制文件路径，并显示已启用的窗口布局按钮 |
| Finder 当前目录背景 | 新建文本文件、复制当前路径、在终端打开，并显示窗口布局按钮 |
| 其他无选中内容场景 | 仅显示已启用的窗口布局按钮 |

Finder 当前目录解析会优先使用辅助功能信息，必要时通过 Automation 查询 Finder。短按右键仍交给系统菜单处理。

### 截图与录屏

- 从菜单栏的“截图与录屏”或 `Option + 3` 进入框选。
- 顶部模式按钮默认选择截图，也可在框选前切换为录屏；框选完成后直接执行当前模式。
- 截图在原选区内编辑，支持线条、自由画笔、箭头、长方形、八种预置颜色、三档线宽、马赛克和撤销；粗细按钮以实际笔触展示，最后选择的工具、颜色与线宽保留到下次使用，旧版自定义颜色会自动匹配到最接近的预置色，马赛克完成后不显示彩色边框。
- 截图完成后写入系统剪贴板，不额外落盘；录屏停止按钮吸附在所选屏幕顶部中央，视频不包含音频，文件保存到 `~/Downloads/`。
- 同一时间只允许一个截图或录屏会话。

## 技术结构

项目包含一个可执行 target 和一个可复用核心库：

- `MacTools`：应用入口、菜单栏、运行时装配、全局右键监听、窗口控制、Finder 集成和 ScreenCaptureKit 采集。
- `MacToolsCore`：剪贴板、SQLite 存储、设置、快捷键、权限、右键状态机、翻译、窗口布局算法、截图状态/渲染和 SwiftUI 组件。

```text
.
├── Package.swift
├── Sources
│   ├── MacTools
│   │   ├── App
│   │   │   └── ScreenCapture
│   │   └── MacToolsMain.swift
│   └── MacToolsCore
│       ├── Clipboard
│       ├── FileActions
│       ├── HotKeys
│       ├── Panels
│       ├── Paste
│       ├── Permissions
│       ├── RightClick
│       ├── ScreenCapture
│       ├── Settings
│       ├── Storage
│       ├── Sync
│       ├── Translation
│       ├── UI
│       ├── Utilities
│       └── WindowLayout
├── Tests/MacToolsCoreTests
├── docs
└── scripts
```

详细架构图见 [docs/architecture/mac-tools-architecture.html](docs/architecture/mac-tools-architecture.html)，macOS 行为验收清单见 [docs/manual-verification.md](docs/manual-verification.md)。

## 环境要求

- macOS 26 或更高版本。
- Xcode 或 Xcode Command Line Tools，Swift 工具链需兼容 SwiftPM tools version `5.10`。
- 首次构建需要网络访问以解析 [GRDB.swift](https://github.com/groue/GRDB.swift) 依赖。

```sh
swift --version
```

## 构建与运行

### 单元测试

```sh
swift test
```

### SwiftPM 开发运行

```sh
swift run MacTools
```

该方式适合常规开发，但 Finder Automation 授权与签名身份绑定，不适合验证相关 TCC 行为。

### 构建并启动本地 App

```sh
scripts/rebuild_and_run_app.sh
```

仅构建并签名 App Bundle：

```sh
scripts/package_app.sh
open build/MacTools.app
```

`package_app.sh` 优先使用 `MACOS_CODESIGN_IDENTITY`，否则尝试从钥匙串选择 Apple/Developer 签名身份；找不到时退回 ad-hoc 签名。ad-hoc 签名可能导致辅助功能、输入监控和屏幕录制授权无法稳定继承。

```sh
MACOS_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/package_app.sh
```

## 权限

| 系统权限 | 使用场景 |
| --- | --- |
| 辅助功能 | 选区捕获、自动粘贴、读取/移动当前窗口 |
| 输入监控 | 监听全局右键按下与抬起事件 |
| 屏幕录制 | 区域截图和区域录屏 |
| Finder Automation | Finder 当前目录辅助解析，仅在需要回退查询时触发 |

权限与签名身份关联。首次运行、签名变化或权限异常时，应从 `build/MacTools.app` 启动并在“系统设置 → 隐私与安全性”中重新授权。辅助功能和输入监控可按需重置：

```sh
tccutil reset Accessibility local.mactools.mvp
tccutil reset ListenEvent local.mactools.mvp
scripts/rebuild_and_run_app.sh
```

## 本地数据与安全边界

运行数据默认位于 `~/Library/Application Support/MacTools/`：

| 路径 | 内容 |
| --- | --- |
| `Store/mactools.sqlite3` | 剪贴板元数据、普通配置、设备覆盖和同步状态；`-wal`、`-shm` 是同一 SQLite 数据库的运行时伴随文件 |
| `Store/Payloads/objects/` | 经过校验并按 SHA-256 去重的原始剪贴板图片 |
| `Store/Payloads/staging/` | 图片写入和迁移过程中的临时文件，成功后原子移入对象库 |
| `settings.json`、`Clipboard.sqlite`、`ClipboardCache/` | 一次性迁移和回滚来源，不再参与正常运行时读写 |
| `debug.log` | 运行诊断日志 |

百炼 API Key 只存入本机 Keychain，不进入 SQLite、同步快照或 iCloud Drive 内容对象，也不会随其他配置同步；新设备需要单独填写。同步目录中的普通文字和图片不做应用层加密，数据保护依赖用户的 iCloud 账号与系统权限。不要把数据库、Payload、同步目录、旧迁移源、日志、录屏文件或真实剪贴板内容复制到仓库、测试夹具和问题报告中。

## 排障与验收

超级右键诊断：

```sh
scripts/diagnose_super_right_click.sh
scripts/diagnose_super_right_click.sh --clear-log --probe
```

常见定位边界：

- 没有 `right mouse down`：检查输入监控、进程和签名。
- 有 `long press triggered` 但捕获为空：检查辅助功能和目标应用是否支持选区读取。
- 已捕获内容但没有预期动作：检查内容分类、Finder 当前目录解析和窗口布局配置。
- 已生成动作但没有浮层：检查 `NSPanel` 展示与透明圆角配置。

详细链路见 [docs/super-right-click-debuggable-design.md](docs/super-right-click-debuggable-design.md)。涉及 UI、TCC、Finder Automation、截图录屏或签名的改动，除 `swift test` 外还应执行 [docs/manual-verification.md](docs/manual-verification.md) 中对应场景。

## 开发约定

- AppKit 系统集成保留在 `Sources/MacTools/App`，可测试业务逻辑优先放入 `MacToolsCore`。
- 系统服务通过协议或闭包注入，行为变化补充 `Tests/MacToolsCoreTests` 中的聚焦测试。
- UI 改动必须运行 `scripts/rebuild_and_run_app.sh`，并在明暗背景检查所有受影响面板的圆角、阴影、标题栏残留和外层 backing layer。
- 不提交 `.env*`、凭证、`.idea/`、`build/`、`.build/`、SQLite、剪贴板缓存、运行日志和本地用户数据。
