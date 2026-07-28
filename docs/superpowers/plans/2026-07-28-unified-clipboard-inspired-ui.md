# MacTools 统一界面 Implementation Plan

**Goal:** 以当前剪贴板页面为视觉基准，统一设置、翻译、超级右键、截图选区、截图编辑器和录屏控制条，同时保持现有业务与窗口行为。

**Architecture:** 扩展现有 `MacToolsGlassTheme`、`LiquidGlassSurfaceStyle` 和语义尺寸，建立默认透明、悬停中性、选中浅蓝和主操作系统蓝四层表面。主工作区复用统一页头和选择样式；紧凑面板复用同一组颜色、圆角与按钮。AppKit 控制器继续拥有窗口生命周期，必要时使用 `NSHostingView` 承载 SwiftUI 内容。

**Tech Stack:** Swift 5.10、SwiftUI、AppKit、macOS 26 Liquid Glass、SwiftPM、XCTest。

## Global Constraints

- 不修改设置模型、数据库、剪贴板存储、翻译请求、快捷键、权限或截图录屏管线。
- 保持超级右键的面板尺寸、窗口层级、滚动和外部点击关闭行为。
- 保持截图编辑设置防抖保存、取消、撤销和完成行为。
- 所有 UI 修改同时支持浅色、深色、键盘焦点和减少动态效果。
- 仅提交本计划涉及的源代码、测试、人工验证文档和计划文件。

## Task 1：统一视觉基础

**Files:**
- Modify: `Sources/MacToolsCore/UI/MacToolsGlassTheme.swift`
- Modify: `Sources/MacToolsCore/UI/LiquidGlassSurface.swift`
- Modify: `Tests/MacToolsCoreTests/LiquidGlassSurfaceTests.swift`

- [x] 补充统一页面、页头、分类、紧凑面板和截图工具栏语义尺寸。
- [x] 增加中性悬停、浅蓝选择、焦点和紧凑面板表面角色。
- [x] 增加可复用的行表面、选择按钮和主次操作样式。
- [x] 运行 `swift test --filter LiquidGlassSurfaceTests`。

## Task 2：统一设置、剪贴板和翻译

**Files:**
- Modify: `Sources/MacToolsCore/UI/MainWorkspaceView.swift`
- Modify: `Sources/MacToolsCore/UI/MainPanelView.swift`
- Modify: `Sources/MacToolsCore/UI/ClipboardRowView.swift`
- Modify: `Sources/MacToolsCore/UI/SettingsView.swift`
- Modify: `Sources/MacToolsCore/UI/SettingsNavigation.swift`
- Modify: `Sources/MacToolsCore/UI/SettingsComponents.swift`
- Modify: `Sources/MacTools/App/RuntimeViews.swift`
- Modify: related UI tests

- [x] 让工作区统一提供页面边距，移除设置和翻译的重复 padding。
- [x] 将 `MainWorkspaceModuleHeader` 改为剪贴板同款扁平页头。
- [x] 设置分类复用剪贴板选择语言，移除实色设置内容卡片。
- [x] 翻译移除说明、输入和输出的多层模块表面，保留双栏与状态。
- [x] 保持剪贴板搜索、分类、列表选择和键盘行为。
- [x] 运行设置、剪贴板、翻译和主工作区聚焦测试。

## Task 3：统一超级右键

**Files:**
- Modify: `Sources/MacToolsCore/UI/ContextActionView.swift`
- Modify: `Sources/MacToolsCore/UI/SuperPanelLayout.swift` when required
- Modify: related super-panel tests

- [x] 外壳改用共享紧凑 Liquid Glass 表面。
- [x] 页头、预览、动作行和布局按钮收敛为扁平内容与统一悬停状态。
- [x] 移除动作类型的装饰性色块，只保留必要语义色。
- [x] 保持现有内容驱动尺寸、滚动上限和动作集合。
- [x] 运行超级右键布局、内容、快照和窗口外观聚焦测试。

## Task 4：统一截图选区与编辑器

**Files:**
- Modify: `Sources/MacTools/App/ScreenCapture/ScreenSelectionOverlayController.swift`
- Modify: `Sources/MacTools/App/ScreenCapture/ScreenshotEditorView.swift`
- Modify: `Sources/MacToolsCore/ScreenCapture/ScreenCaptureOverlayLayout.swift`
- Modify: related screen-capture tests

- [x] 将截图或录屏模式控件改为共享紧凑玻璃选择样式。
- [x] 将截图编辑工具栏改为单排：工具、参数、取消和完成。
- [x] 颜色与粗细按钮显示当前值，并使用原生 popover 选择。
- [x] 宽度不足时隐藏选中工具文字，保持单排。
- [x] 更新工具栏高度与显示器边界布局测试。
- [x] 运行截图布局、会话、展示与录制相关聚焦测试。

## Task 5：统一录屏控制条

**Files:**
- Modify: `Sources/MacTools/App/ScreenCapture/RecordingControlPanelController.swift`
- Modify: `Tests/MacToolsCoreTests/RecordingControlPanelSourceTests.swift`

- [x] 使用 SwiftUI 内容和共享紧凑玻璃外壳。
- [x] 展示红色录制状态点、等宽计时和弱红停止按钮。
- [x] 保持现有非激活面板、层级、跨空间、计时和停止回调。
- [x] 运行录屏控制条与截图覆盖层聚焦测试。

## Task 6：文档、全量测试与视觉验证

**Files:**
- Modify: `docs/manual-verification.md`

- [x] 更新设置、主工作区、超级右键、截图工具栏和录屏控制条人工检查项。
- [x] 运行全部相关聚焦测试。
- [x] 运行完整 `swift test`。
- [x] 运行 `scripts/rebuild_and_run_app.sh`。
- [ ] 在浅色和深色背景上逐页检查尺寸、焦点、外部点击、键盘导航和圆角背板。
- [ ] 验证截图颜色或粗细 popover、带标注 PNG、录屏停止与可播放 MP4。
- [x] 运行 `git diff --check` 和受控范围敏感词扫描。
- [ ] 只暂存本任务文件，创建中文 commit 并推送当前远程分支。
