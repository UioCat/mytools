# AGENTS.md

## 项目概览

MacTools 是一个使用 Swift Package Manager 构建、面向 macOS 26 及以上版本的菜单栏应用。已实现的功能包括剪贴板历史、百炼翻译与系统语音朗读、超级右键操作、区域截图与屏幕录制、窗口布局、设置和权限诊断。应用采用辅助应用激活策略运行，默认不显示 Dock 图标。

## 仓库结构

| 路径 | 职责 |
| --- | --- |
| `Package.swift` | `MacTools` 可执行程序和 `MacToolsCore` 库的 SwiftPM 定义；外部依赖为 GRDB.swift |
| `Sources/MacTools` | AppKit 入口、运行时依赖装配、菜单栏、面板、Finder 集成、全局右键监控和 ScreenCaptureKit 实现 |
| `Sources/MacTools/App/ScreenCapture` | 选区覆盖层、截图编辑器、静态截图、MP4 录制器和录制控制 |
| `Sources/MacToolsCore` | 可复用的模型、服务、状态机、持久化、设置、权限、翻译、窗口布局逻辑、截图渲染和 SwiftUI 视图 |
| `Tests/MacToolsCoreTests` | 聚焦的单元测试以及 UI 决策和快照辅助工具 |
| `scripts/package_app.sh` | 发布构建、本地 `.app` 组装，以及受信任签名或临时签名 |
| `scripts/rebuild_and_run_app.sh` | 重新构建、替换正在运行的应用，并启动 `build/MacTools.app` |
| `scripts/diagnose_super_right_click.sh` | 检查打包应用、TCC 状态、进程状态、事件探针和 `debug.log` |
| `docs/manual-verification.md` | 面向 UI、权限、Finder、截图录制和运行时行为的 macOS 人工冒烟测试 |

## 架构边界

- 将 AppKit 和操作系统集成保留在 `Sources/MacTools/App`；将可复用行为与状态保留在 `MacToolsCore`。
- 优先采用 SwiftPM 原生改动。不要仅为配置已经能够通过 `Package.swift` 或脚本表达的构建行为而添加 Xcode 工程。
- 当逻辑需要可测试时，应注入剪贴板、工作区、事件发送、权限、翻译 HTTP、文件系统、时钟和截图录制服务。
- 保持超级右键各阶段可观察：事件检测、权限预检查、选区或 Finder 解析、分类、操作构建和面板展示。
- 将设置与快捷键视为统一的运行时约定：保存设置后必须立即更新相关服务，无需重启应用。

## 当前产品约定

| 范围 | 必须保持的约定 |
| --- | --- |
| 工具快捷键 | 默认快捷键为：`Option+Space` 打开设置、`Option+1` 打开剪贴板、`Option+2` 打开翻译、`Option+3` 打开截图录制；全部均可配置 |
| 剪贴板 | 使用 SQLite 存储元数据并使用外部文件缓存；执行“清除非收藏项”后收藏项仍须保留；默认历史上限为 500，默认缓存上限为 1024 MB |
| 翻译 | 在线提供方为阿里云百炼，提供方 ID 为 `bailian`，模型为 `qwen-mt-turbo`，使用 DashScope 的 OpenAI 兼容端点；主翻译面板和超级右键译文均支持系统语音朗读 |
| 超级右键 | 短按保留系统菜单；长按阈值可配置为 250、300 或 350 毫秒 |
| 截图录制 | 仅支持用户拖动选择区域；截图会将标注后的 PNG 复制到剪贴板；录屏会将仅含视频的 H.264 MP4 写入“下载”目录 |
| 窗口布局 | 八种内置模式均可显示或隐藏，并可分配一个或多个快捷键；移动其他应用窗口需要辅助功能权限 |

## 命令

```sh
# 迭代时运行聚焦测试
swift test --filter TestCaseName

# 运行完整单元测试套件
swift test

# 开发环境启动
swift run MacTools

# 重新构建、签名并启动应用包
scripts/rebuild_and_run_app.sh

# 仅构建和签名
scripts/package_app.sh

# 超级右键诊断
scripts/diagnose_super_right_click.sh
```

涉及 Finder 自动化、TCC 身份、签名、截图录制或发布行为检查时，必须使用打包后的应用。`swift run MacTools` 不能作为这些行为的验证证据。

## 工作树安全

- 编辑前运行 `git status --short`。除非任务明确包含这些改动，否则现有的已修改文件和未跟踪文件均属于用户工作。
- 进行范围最小且保持行为的改动，并遵循附近代码模式。不要重新格式化或重写无关文件。
- 所有项目文件引用均使用仓库相对路径。仅当操作系统或 API 约定、或者明确任务要求必须使用绝对路径时才可使用；应记录原因，并且不得嵌入真实的用户主目录路径。
- 生成的 `.build/`、`build/`、应用包、本地日志、SQLite 文件、剪贴板缓存、录屏和编辑器元数据均不是源代码产物。
- 不要使用破坏性的 Git 命令移除无关工作。

## 提交与推送

- 每次完成任何源代码、测试、脚本或文档修改并通过必要验证后，必须在本次任务结束前主动创建 Git commit，并 push 到当前分支对应的远程分支；不得等待用户再次提醒，也不得仅把改动留在工作树中。
- Git commit 的标题和正文必须使用中文。标题应概括修改目的，正文应明确说明涉及的文件或模块、具体改动内容及验证结果；包含多项改动时应分条说明，不得只使用“更新”“修复”等无法体现改动内容的笼统描述。
- 面向用户说明提交、合并和推送结果时必须使用中文，并列出本次修改内容、commit 标识、目标远程分支及验证结果。
- 提交和推送前必须核对改动范围、验证结果与目标分支，只暂存和提交本次任务涉及的文件，不得夹带无关的用户改动。
- 如果 commit 或 push 失败，必须说明失败原因、当前分支和未推送的 commit，不得宣称任务已经完成。

## 编码指南

- 行为变更需要在 `Tests/MacToolsCoreTests` 中添加或更新聚焦测试。优先使用确定性的辅助工具，不要编写依赖实时 TCC 状态或当前桌面的测试。
- 保持运行时 UI 文案和权限行为与 `docs/manual-verification.md` 一致；用户可见行为发生变化时更新该检查清单。
- 不要使用 Finder 脚本、翻译 HTTP、截图录制启动或文件 I/O 阻塞主 Actor。保留 Finder 解析中的取消处理和过期结果保护。
- 保持剪贴板载荷分类和持久化向后兼容。数据库或设置模式变更必须包含迁移和默认解码测试。
- 不要通过把产品默认值改为不受支持的按键来掩盖快捷键注册失败；Carbon 按键支持位于 `HotKeyService`。

## UI 视觉验证

每次 UI 变更后：

1. 运行 `scripts/rebuild_and_run_app.sh`。
2. 在明暗对比明显的背景上检查每个受影响面板。
3. 验证尺寸调整、焦点变化、外部点击关闭、键盘导航以及相关权限状态。

任何出现在预期圆角 Liquid Glass 表面之外的意外灰色轮廓、标题栏残留、矩形系统阴影或背板层，均属于发布阻断问题。对于 `NSPanel` 表面，应检查 AppKit 样式掩码、`hasShadow`、透明度和圆角背板层裁切，不要在 SwiftUI 内部通过遮盖窗口边框来处理。

## 权限与运行时验证

| 变更范围 | 单元测试之外的必需证据 |
| --- | --- |
| 超级右键或自动粘贴 | 使用打包应用并授予辅助功能和输入监控权限进行检查；确认短按仍会打开系统菜单 |
| Finder 当前文件夹解析 | 使用打包应用检查已授权、首次弹窗、拒绝或撤销、超时、取消和过期结果场景 |
| 窗口布局 | 通过面板操作和已配置快捷键，在当前显示器上移动聚焦窗口 |
| 截图或录屏 | 验证屏幕录制权限流程、区域选择、取消路径、带标注的剪贴板 PNG、可播放的 MP4 和重复会话防护 |
| 打包或签名 | 运行 `scripts/package_app.sh`，按需检查签名，并启动 `build/MacTools.app` |

## 隐私与密钥

- 不得向源代码、测试、测试数据、快照或文档中添加凭据、Authorization 请求头、剪贴板内容、用户路径、录屏或运行时日志。
- 百炼 API Key 使用 `Store/Credentials/` 下权限为 `0600` 的 AES-GCM 信封保存，并可通过已选择的 iCloud Drive 同步目录保存加密 replica。固定派生材料是公开协议常量，不得描述为真正秘密；不得新增明文副本、把凭据写入 SQLite/普通同步快照，或在日志和错误中暴露值。旧 `settings.json` 与 Keychain 仅作为一次性只读迁移源。
- 将 `Clipboard.sqlite`、`ClipboardCache/`、`settings.json`、`debug.log`、仓库本地 `log/`，以及包含类似剪贴板内容的测试数据视为敏感用户数据。
- 测试中使用临时目录，文档中使用仓库相对路径。不得硬编码真实绝对用户路径。
- 提交前扫描受源代码控制的范围，查找可能的密钥，且不得输出本地运行时数据：

```sh
rg -n --hidden \
  --glob '!.git/**' \
  --glob '!.worktrees/**' \
  --glob '!.build/**' \
  --glob '!build/**' \
  --glob '!log/**' \
  -i 'api[_ -]?key|access[_ -]?key|secret|token|password|credential|private[_ -]?key|client[_ -]?secret|app[_ -]?secret|authorization|bearer|cookie|session'
```

根据上下文审查匹配结果：API 字段名和测试占位值属于预期内容，真实值则不允许存在。

## 完成前验证

- 仅文档变更：检查链接、命令和路径，并运行 `git diff --check`；当文档声明或更改可执行行为时运行测试。
- 核心行为变更：先运行范围最小的相关测试，再运行 `swift test`，之后才能宣称完成。
- UI、权限、Finder、截图录制或打包变更：补充执行上文适用的人工检查；如果无法执行，明确说明未验证边界和剩余风险。
- 不要仅凭编译成功或进程已启动就宣称成功。必须验证该变更描述的用户可见结果。
