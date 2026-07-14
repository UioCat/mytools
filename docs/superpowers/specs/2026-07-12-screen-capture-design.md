# 工具 3：框选截图与录屏设计

## 目标

将 MacTools 的「工具 3」（默认 `Option+3`）升级为统一的屏幕采集入口：用户只能手动框选单个显示器中的一个矩形区域，并可通过屏幕顶部吸附的模式按钮切换「截图」或「录屏」；默认模式为截图。

- 截图：框选后进入编辑器，支持划线、箭头、长方形、圆形、颜色选择和马赛克；确认后将编辑结果复制到系统剪贴板。
- 录屏：框选后开始录制该区域的画面；停止后将 MP4 文件保存到用户的“下载”目录。

首期不支持全屏、窗口捕捉、跨显示器框选、系统音频、麦克风、摄像头、GIF、云同步或录屏后的二次编辑。

## 用户流程

1. 用户按下 `Option+3`，或从菜单栏菜单选择「截图与录屏」。
2. MacTools 检查屏幕录制权限；未获得权限时不显示采集界面，而是显示明确说明和“打开系统设置”动作。
3. 获得权限后，在每块显示器上显示无边框、无阴影、且不被采集的深色半透明选区浮层。
4. 用户在一个显示器内拖动鼠标，得到矩形区域；小于最小尺寸的拖动不进入下一步。`Esc` 随时取消。
5. 当前显示器顶部展示吸附的「截图 / 录屏」模式按钮，默认选中截图；用户切换模式后再框选区域，框选完成即执行当前模式，不需要二次确认。
6. 截图流程在选区完成后取得静态图像，并直接在原选区位置进入标注：
   - 默认工具为划线；工具条包含划线、箭头、长方形、圆形、马赛克、撤销、取消、完成。
   - 划线、箭头、长方形和圆形支持八种常用颜色、自定义颜色及细/标准/粗三档线宽；最后选择的颜色和线宽写入现有设置并用于下次截图。马赛克拖拽时显示选区边界，完成后仅保留真实像素化效果，不显示彩色边框；全部标注均可撤销。
   - 点击“完成”时，编辑器在后台将原图与全部标注合成为 PNG 并写入通用剪贴板；完成后关闭编辑器，不额外保存到磁盘。
7. 录屏流程隐藏浮层，立即开始采集选区；在所选显示器顶部中央显示吸顶且不可被录入的悬浮控制条，包含红色状态、计时和“停止”。停止后结束流、完成 MP4 写入，并在 Finder 中选中该文件。

## 架构与职责

### MacToolsCore：可测试规则与图像模型

在 `Sources/MacToolsCore/ScreenCapture/` 增加与 AppKit 无关的值类型和协议：

- `ScreenCaptureMode`：`.screenshot`、`.recording`。
- `ScreenCaptureSelection`：显示器标识与该显示器坐标系中的矩形；负责最小尺寸校验和像素对齐。
- `ScreenshotAnnotation`：划线、箭头、长方形、圆形、颜色、线宽和马赛克的绘制描述；`ScreenshotAnnotationStore` 负责追加、撤销和合成顺序，`ScreenCaptureSettings` 负责保存用户最后选择的颜色与线宽。
- `ScreenCaptureDestination`：根据注入的 Downloads URL 生成无冲突的 `MacTools Recording yyyy-MM-dd HH.mm.ss.mp4` 输出 URL。
- `ScreenCaptureSessionState`：从选区、采集、编辑、录制到完成/取消的状态机，防止重复开始、重复停止或在无效选区上启动采集。
- `ScreenCapturing`、`ScreenRecording` 和 `ScreenshotClipboardWriting` 协议：为 ScreenCaptureKit、AVAssetWriter 与 `NSPasteboard` 提供 App 层实现，并允许 Core 测试使用假实现。

Core 只保存标注的几何描述与导出决策；不持久化任何原始截图、图像字节或录屏数据。

### MacTools App：窗口、系统集成与运行时协调

在 `Sources/MacTools/App/ScreenCapture/` 增加以下 AppKit/SwiftUI 适配层：

- `ScreenSelectionOverlayController`：按显示器创建非激活、borderless 面板，捕获拖拽和 `Esc`，将全局 AppKit 坐标转换为所选显示器中的选择坐标；顶部吸附按钮维护当前截图或录屏模式，默认截图。
- `SystemScreenCaptureService`：在选区浮层出现时预取并在单次会话内复用 `SCShareableContent`，再用 `SCContentFilter`、`SCStreamConfiguration.sourceRect` 与 `SCStream` 取得选区画面。它显式排除 MacTools，保证浮层、编辑器与录制控制条不出现在结果中。
- `MP4ScreenRecorder`：将 `SCStream` 视频 sample buffers 写入 `AVAssetWriter` 的 H.264 MP4；以 30 fps、带鼠标指针的画面为默认录制设置，不添加任何音频输入。
- `ScreenshotEditorPanelController` 与 `ScreenshotEditorView`：在原选区位置展示静态图像和可交互的标注画布，工具条优先贴近选区下方并保持在当前屏幕内。画布坐标先映射到原始图片像素，再在完成时通过 Core Image/CGContext 后台合成 PNG。
- `ScreenCaptureCoordinator`：拥有单次会话，顺序调用权限检查、选区浮层、截图/录屏服务、编辑器、剪贴板写入及 Finder reveal；无论成功、失败或取消都释放面板和流。

`AppEnvironment.openScreenCapture()` 创建或复用协调器；`AppDelegate` 将原 `.reservedTool3` 热键派发替换为此方法，`MenuBarController` 也提供同一入口。设置界面把文字「工具 3」改为「截图与录屏」，快捷键配置和用户既有 `reservedTool3Shortcut` 存储键保持不变，避免破坏已有设置。

## 权限与错误处理

在 `PermissionService` 中新增 `screenRecording` 权限和对应的系统设置深链接。实际开始 ScreenCaptureKit 操作前，`SystemScreenCaptureService` 再用系统 API 验证授权，避免因系统设置刚修改但设置页面摘要尚未刷新而误报成功。

- 未授权：显示“需要屏幕录制权限”的提示，并提供“打开系统设置”；不创建采集流。
- 用户取消、空选区或跨显示器拖拽：清理浮层，不写剪贴板、不创建文件、不显示错误弹窗。
- 静态图像、流初始化、编码、写文件或写剪贴板失败：关闭全部临时 UI，写诊断日志，并显示一条可理解的错误信息；失败的 MP4 临时文件被删除。
- 如果下载目录不可写：记录失败并告知用户，绝不改写到其他目录。
- 录屏过程中再次触发 `Option+3`：忽略新请求，让当前会话继续；录制控制条的停止操作是唯一结束入口。

## 视觉和交互约束

- 选区浮层、工具条、编辑器和录制控制条延续现有 Liquid Glass、连续圆角、系统蓝强调色与 8 点间距。
- 浮层面板遵守项目 `AGENTS.md` 的 borderless、无系统阴影、透明 backing layer 与圆角裁切要求；灰色方形边、标题栏残留或框外 backing layer 视为阻塞问题。
- 鼠标框选在一个显示器中完成；拖动穿越显示器边界时，选区限制在起始显示器内。
- 顶部模式按钮和原位编辑工具条必须保持在当前显示器可见区域内。编辑器快捷键：`Esc` 取消，`Command+Z` 撤销，`Command+Return` 完成并复制。录制控制条的停止按钮提供可访问性标签。

## 测试与验收

遵循测试驱动开发：每个 Core 规则先写失败测试，再实现最小行为。

- `ScreenCaptureSelection`：最小尺寸、显示器边界裁剪、像素对齐和跨显示器限制。
- `ScreenCaptureSessionState`：截图与录屏状态迁移、取消、拒绝重复启动以及失败后的资源释放决策。
- `ScreenCaptureMode` 与 `ScreenCaptureOverlayLayout`：默认截图模式、顶部吸附位置、原位编辑工具条的优先位置和屏幕边界约束。
- `ScreenshotAnnotationStore`：划线、箭头、长方形、圆形和马赛克按顺序追加、保留所选颜色与线宽、撤销和空状态；设置往返测试验证颜色与线宽跨会话保留，渲染测试验证马赛克确实改变区域像素且完成后不显示选区边框。
- `ScreenCaptureDestination`：Downloads 默认目录、文件命名、同名冲突的递增后缀及不可写目录错误。
- `HotKeyService` / `AppDelegate`：`Option+3` 路由到截图与录屏而非预留日志。
- `PermissionService`：屏幕录制权限摘要与系统设置 URL。
- App 层以注入的假采集器、录制器和剪贴板验证：截图完成复制 PNG；录屏停止只产生 Downloads 下的 MP4 并触发 Finder reveal。

完成前运行全量 `swift test`、`git diff --check` 和隐私敏感词扫描；再运行 `scripts/rebuild_and_run_app.sh`，在浅色与深色背景上手动检查选区浮层、截图编辑器和录制控制条。实际采集验证至少覆盖：首次权限提示、截图复制、划线/箭头/长方形/圆形、常用色与自定义颜色、三档线宽、颜色与线宽跨会话保留、马赛克完成后无彩色边框、取消、录屏 MP4 下载、顶部停止按钮和错误提示。

## Apple 平台依据

项目最低目标是 macOS 26。录屏使用 ScreenCaptureKit，而非 `AVCaptureScreenInput`；Apple 已将后者标为从 macOS 12.3 起应由 ScreenCaptureKit 替代。ScreenCaptureKit 的 `SCStream` 根据 `SCContentFilter` 与 `SCStreamConfiguration` 捕获画面，并把视频 sample buffers 提供给应用写入 MP4。

- https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos
- https://developer.apple.com/documentation/avfoundation/avcapturescreeninput
