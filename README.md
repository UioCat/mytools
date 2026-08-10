# MacTools

一款常驻菜单栏的原生 macOS 效率工具，把剪贴板、翻译、超级右键、截图录屏和窗口布局集中到一个轻量应用里。

MacTools 默认不显示 Dock 图标，需要时通过菜单栏或全局快捷键立即唤起。所有主要功能都可在应用内配置，无需重启。

> 当前支持 macOS 26 及以上版本。下方截图来自实际打包应用，使用专门准备的演示数据，不包含个人剪贴板、账户、路径或 API Key。

## 核心功能

| 功能 | 你可以做什么 |
| --- | --- |
| **剪贴板历史** | 自动记录文本、链接、文件、文件夹和图片；支持搜索、分类、收藏、删除，以及复制后自动粘贴 |
| **百炼翻译** | 中文自动翻译成英文，英文及其他语言自动翻译成中文；支持复制译文和系统语音朗读 |
| **超级右键** | 短按继续使用系统右键菜单，长按快速处理选中文本、Finder 项目或当前文件夹 |
| **截图与录屏** | 自由框选屏幕区域；截图支持画笔、箭头、矩形、颜色、线宽和马赛克，录屏输出 H.264 MP4 |
| **窗口布局** | 一键将当前窗口调整为半屏、1/3、2/3、居中或满屏，并可为每种布局配置多个快捷键 |
| **统一设置** | 管理外观、快捷键、统一存储、iCloud Drive 同步、超级右键响应速度、翻译服务、窗口布局和权限状态 |

## 界面预览

<table>
  <tr>
    <td width="50%" align="center">
      <img src="docs/images/clipboard-history.png" alt="MacTools 剪贴板历史" />
      <br />
      <strong>剪贴板历史</strong><br />搜索、分类、收藏并快速复用最近内容
    </td>
    <td width="50%" align="center">
      <img src="docs/images/translation.png" alt="MacTools 百炼翻译" />
      <br />
      <strong>百炼翻译</strong><br />双栏查看原文和译文，并可复制或朗读
    </td>
  </tr>
  <tr>
    <td width="50%" align="center">
      <img src="docs/images/super-right-click.png" alt="MacTools 超级右键" />
      <br />
      <strong>超级右键</strong><br />长按右键直接翻译、复制或中转选中文本
    </td>
    <td width="50%" align="center">
      <img src="docs/images/screenshot-editor.png" alt="MacTools 截图标注编辑器" />
      <br />
      <strong>截图标注</strong><br />在原选区内完成标注、马赛克和复制
    </td>
  </tr>
</table>

## 功能详情

### 剪贴板历史

- 应用每 `0.75` 秒轮询一次系统剪贴板；普通历史固定保留 `500` 条，新增时按最后捕获或使用时间懒淘汰，收藏和置顶不参与自动淘汰。
- `全部 / 文本 / 图像 / 收藏` 四个分类支持鼠标和键盘切换。
- 剪贴板元数据、普通配置和同步状态统一保存在 `Store/mactools.sqlite3`；直接复制的原始图片进入 `Store/Payloads/` 内容寻址对象库。
- 图片按 SHA-256 去重；记录删除或淘汰后，无引用原图由可重试 GC 自动回收。存储位置和容量不提供自定义入口。
- 收藏记录不会被“清空未收藏记录”删除。

### iCloud Drive 同步

- 在“设置 → 数据与同步”选择一个 iCloud Drive 普通文件夹；该方案不使用 CloudKit、应用专属 iCloud Container、APNs 或 Provisioning Profile，免费开发者账号和 ad-hoc 签名包也可使用。
- 本地 SQLite 始终是运行时数据源，不会同步 `mactools.sqlite3`、`-wal`、`-shm` 或本地 Payload 目录。每台 Mac 只写自己的紧凑快照，共享文字和图片按 SHA-256 内容寻址去重。
- 同步范围包含文字、URL、直接复制的原始图片、收藏/置顶状态、普通配置和百炼 API Key 加密副本；Finder 文件路径不跨设备同步。
- 云端普通历史全局最多 500 条；默认同步目录预算为 512 MiB，可选 256 MiB、512 MiB、1 GiB 或 2 GiB。单张图片最大 64 MiB，收藏和置顶不会被容量策略自动删除。
- 无引用共享对象经过 24 小时稳定观察且所有可见设备快照可验证后才会回收；目录或文件尚未下载时暂停回收，不影响本地剪贴板使用。
- 单个本地图片缺失或单个远端内容对象损坏时会隔离该记录，文字、配置和删除操作仍继续同步；持有正确本地内容的设备可按同一 SHA-256 原子修复损坏对象。
- 设置页列出当前可见设备；移除长期离线设备后，它不再阻塞墓碑压缩和对象回收，若重新上线会自动换用新的设备身份。

### 百炼翻译

- 使用阿里云百炼 `qwen-mt-turbo` 模型和 DashScope OpenAI 兼容接口。
- 自动判断翻译方向：中文译为英文，其他语言译为中文。
- 原文和译文都可使用 macOS 系统音色朗读，也可以一键复制译文。
- 使用前需在设置中填写自己的 `DASHSCOPE_API_KEY`。

### 超级右键

长按右键会根据当前内容展示不同动作；普通短按仍然打开系统右键菜单。

| 当前场景 | 可用动作 |
| --- | --- |
| 选中文本 | 查看翻译、朗读、复制译文、打开文本悬浮中转 |
| Finder 已选项目 | 复制文件路径、使用已启用的窗口布局 |
| Finder 当前文件夹 | 新建文本文件、复制目录路径、在终端打开、调整窗口布局 |
| 其他窗口 | 使用已启用的窗口布局 |

长按响应速度可选择 `250 / 300 / 350 ms`。

### 截图与录屏

- 从菜单栏或快捷键进入，在当前显示器上拖动选择区域。
- 截图支持线条、自由画笔、箭头、矩形、八种颜色、三档线宽、马赛克和撤销。
- 完成后的 PNG 直接写入剪贴板，不额外保存文件。
- 录屏生成不含音频的 H.264 MP4，并保存到“下载”目录。
- 同一时间只允许一个截图或录屏会话，按 `Esc` 可取消。

### 窗口布局

支持左/右半屏、上/下半屏、左/右 `1/3`、左/右 `2/3`、居中和满屏十种模式。每种布局都可以：

- 在超级右键面板中显示或隐藏。
- 添加一个或多个全局快捷键。
- 直接作用于当前聚焦窗口。

重复执行方向布局时，如果窗口仍在上一次成功布局的边缘，会继续移动到该方向相邻显示器的内侧边缘；没有相邻显示器时保持在当前显示器，不循环跳转。

## 默认快捷键

所有快捷键都可以在设置中修改。

| 快捷键 | 动作 |
| --- | --- |
| `Option + Space` | 打开设置 |
| `Option + 1` | 打开剪贴板历史 |
| `Option + 2` | 打开翻译 |
| `Option + 3` | 启动截图与录屏 |
| `Control + Command + ← / →` | 左/右半屏 |
| `Control + Command + ↑ / ↓` | 上/下半屏 |
| `Control + Option + ← / →` | 左/右 `1/3` |
| `Option + Command + ← / →` | 左/右 `2/3` |
| `Control + Option + 0` | 窗口居中 |
| `Control + Command + 0` | 窗口满屏 |

## 安装与运行

### 系统要求

- macOS 26 或更高版本。
- Xcode 或 Xcode Command Line Tools。
- 首次构建需要联网下载 [GRDB.swift](https://github.com/groue/GRDB.swift) 和 [Sparkle](https://github.com/sparkle-project/Sparkle) 依赖。

普通使用请从 [GitHub Releases](https://github.com/UioCat/mytools/releases) 下载 DMG，将 `MacTools.app` 拖入 `/Applications`。每台 Mac 首次打开自签名版本时仍需在“隐私与安全性”选择“仍要打开”；固定匿名签名只用于保持后续版本身份，不会绕过 Gatekeeper。

### 从源码构建

```sh
git clone https://github.com/UioCat/mytools.git
cd mytools
MACOS_SIGNING_MODE=development scripts/rebuild_and_run_app.sh
```

开发模式会以 `MacTools Dev` / `local.mactools.development` 构建并启动 `build/MacTools Dev.app`，不连接正式更新源，也不会与正式版同时运行，避免占用正式版本的系统权限身份或并发访问同一份本地数据。维护者已在 Keychain 配置固定匿名身份后，可直接运行 `scripts/rebuild_and_run_app.sh`；稳定模式会验证签名、原子替换并只启动 `/Applications/MacTools.app`，缺少或不信任固定身份时立即失败。

## 系统权限

MacTools 只在使用对应功能时需要以下权限：

| 权限 | 用途 |
| --- | --- |
| 辅助功能 | 读取选中文本、自动粘贴、获取并移动当前窗口 |
| 输入监控 | 识别全局右键的短按和长按 |
| 屏幕与系统音频录制 | 获取用户框选的截图或录屏区域 |
| Finder 自动化 | 在辅助功能信息不足时读取 Finder 当前文件夹 |

首次运行时，请根据应用内权限状态前往“系统设置 → 隐私与安全性”完成授权。从旧 ad-hoc 版本迁移时，可在权限页使用“整理旧权限记录”，然后重新允许四项权限并重启 MacTools；它只清理当前 MacTools Bundle ID，不影响其他应用。无法按 Bundle ID 清理的旧裸可执行文件条目需在系统设置中用减号删除一次。Finder、超级右键、截图录屏和窗口布局应使用 `/Applications/MacTools.app` 验证，`swift run MacTools` 不适合作为正式系统权限行为的最终运行方式。

## 数据与隐私

运行数据默认位于 `~/Library/Application Support/MacTools/`：

| 路径 | 内容 |
| --- | --- |
| `Store/mactools.sqlite3` | 剪贴板元数据、普通配置、设备覆盖和同步状态 |
| `Store/Payloads/objects/` | 经过校验并按 SHA-256 去重的原始剪贴板图片 |
| `Store/Payloads/staging/` | 图片写入和迁移过程中的临时文件 |
| `Store/Credentials/` | 百炼 API Key 的 AES-GCM 本地加密信封和一次性迁移标记 |
| `settings.json`、`Clipboard.sqlite`、`ClipboardCache/` | 一次性迁移和回滚来源，不参与正常运行时读写 |
| `debug.log` | 运行诊断日志 |

百炼 API Key 不进入 SQLite、普通配置快照或共享内容对象；它使用 AES-GCM 加密信封保存在本地，并在已启用同步时写入 `credentials/replicas/`。升级后的首次启动只把旧 Keychain 或旧明文作为一次性只读迁移源，后续构建不再依赖 Keychain。加密派生材料随 App 公开分发，因此该加密主要避免文件被直接查看或误采集时暴露明文，不抵御拿到 App 与密文后的逆向解密。同步目录中的普通文字和图片仍不做应用层加密，数据保护依赖用户的 iCloud 账号与系统权限。请勿将数据库、Payload、同步目录、旧迁移源、日志、录屏文件或真实剪贴板内容提交到公开仓库。

## 开发者入口

```sh
# 运行完整测试
swift test

# SwiftPM 开发运行
swift run MacTools

# 构建隔离的开发 App Bundle
scripts/package_app.sh

# 构建、安装并启动稳定 App（仅限已配置发布身份的维护者）
scripts/rebuild_and_run_app.sh
```

`package_app.sh` 默认生成隔离 Bundle ID 的 ad-hoc `MacTools Dev`。稳定包必须显式使用 `MACOS_SIGNING_MODE=stable`，并且只接受仓库固定的 `MacTools Release Signing` 证书及指纹；不会自动选择 Apple Development，也不会回退到 ad-hoc。公开证书只包含项目通用名、公钥和密码学元数据，不包含姓名、邮箱或 Apple Team 标识。发布只使用现有 `SPARKLE_PRIVATE_KEY`：GitHub Runner 通过 HKDF-SHA256 用途隔离派生临时 P-256 代码签名子私钥，不需新增证书或密码 Secret，标签发布仍只需 Git Push。

维护者发布稳定版本时，按 [GitHub Release 发布指南](docs/release-guide.md) 完成版本判断、签名预检、标签发布和公开资产复核。

```sh
MACOS_SIGNING_MODE=development scripts/package_app.sh
MACOS_SIGNING_MODE=stable scripts/package_app.sh
```

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

- 应用装配、功能协调和 macOS 系统适配分别位于 `Sources/MacTools/Application`、
  `Sources/MacTools/Features` 和 `Sources/MacTools/Platform`；可测试业务逻辑优先放入 `MacToolsCore`。
- 系统服务通过协议或闭包注入，行为变化补充 `Tests/MacToolsCoreTests` 中的聚焦测试。
- UI 改动必须运行 `scripts/rebuild_and_run_app.sh`，并在明暗背景检查所有受影响面板的圆角、阴影、标题栏残留和外层 backing layer。
- 不提交 `.env*`、凭证、`.idea/`、`build/`、`.build/`、SQLite、剪贴板缓存、运行日志和本地用户数据。

更多资料：

- [架构图](docs/architecture/mac-tools-architecture.html)
- [人工验收清单](docs/manual-verification.md)
- [超级右键诊断设计](docs/super-right-click-debuggable-design.md)
