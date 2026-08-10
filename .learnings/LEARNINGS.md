# Learnings

## [LRN-20260810-002] correction

**Logged**: 2026-08-10T18:30:00+08:00
**Priority**: high
**Status**: pending
**Area**: frontend

### Summary
截图文本与标签的自适应不能只验证排版辅助函数，必须验证生产编辑器创建后的真实对象边界。

### Details
首轮优化的 CoreText 几何测试、原生标签输入框居中测试和渲染快照均通过，但用户在打包应用中仍观察到两类问题：标签在空间充足时提前省略，普通文本选中框仍保留固定大宽度，短文本停留在左上角。现有测试没有覆盖从工具点击、输入、提交到选中边界的完整生产链路，因此没有发现固定文本草稿宽度和标签宽度上限在真实交互中的残留。

### Suggested Action
文本类标注应由内容测量结果生成最终边界，并对生产编辑器补充“输入短文本/长标签 → 提交 → 检查对象边界或最终 PNG”的端到端回归；几何单测只作为底层证据，不能替代真实交互验证。

### Metadata
- Source: user_feedback
- Related Files: `Sources/MacToolsCore/UI/ScreenCapture/ScreenshotEditorView.swift`, `Sources/MacToolsCore/ScreenCapture/ScreenshotTextLayout.swift`, `Tests/MacToolsCoreTests/ScreenshotEditorInteractionTests.swift`
- Tags: screenshot, text, label, adaptive-layout, ui-regression

---

## [LRN-20260725-001] best_practice

**Logged**: 2026-07-25T16:12:38+08:00
**Priority**: medium
**Status**: resolved
**Area**: backend

### Summary
设备 replica 的文件所有者与凭据逻辑时钟的修改来源是两个独立身份。

### Details
`credentials/replicas/<deviceID>.v1.json` 的 device ID 表示哪台设备可以写该文件；信封逻辑
时钟中的 device ID 表示哪台设备产生了获胜修改。其他设备收敛后需要把原信封原样写入自己的
replica，因此两者不能强制相等。

### Suggested Action
只校验 replica 文件名是有效设备 ID，并通过认证信封校验逻辑时钟；允许当前设备转存由其他
设备产生的获胜信封。

### Metadata
- Source: error
- Related Files: `Sources/MacToolsCore/Sync/CredentialReplicaStore.swift`
- Tags: icloud-drive, replica, logical-clock, convergence

### Resolution
- **Resolved**: 2026-07-25T16:12:38+08:00
- **Notes**: 用跨设备转存测试替换错误的身份相等约束。

---

## [LRN-20260810-001] knowledge_gap

**Logged**: 2026-08-10T15:38:39+08:00
**Priority**: low
**Status**: resolved
**Area**: frontend

### Summary
飞书截图的标签颜色只作用于定位点，标签正文保持深色说明气泡。

### Details
初版参考稿把定位点、连接线和标签气泡整体使用同一种标注色。核对飞书官方帮助中心的动态示例后确认，标签主体是固定深灰色气泡，用户选择的颜色仅用于独立定位点；定位点还用于翻转标签方向。

### Suggested Action
参考外部产品设计具体控件时，应查看完整动态示例或多个关键帧，区分不同子元素的颜色和状态规则，避免仅凭首帧、图标或文字说明推断视觉行为。

### Metadata
- Source: error
- Related Files: docs/superpowers/specs/2026-08-10-screenshot-text-label-design.md
- Tags: screenshot, annotation, feishu, label, visual-reference

### Resolution
- **Resolved**: 2026-08-10T15:38:39+08:00
- **Notes**: 最终 UI 设计改为深色标签气泡、独立彩色定位点，并保留定位点翻转交互。

---

## [LRN-20260727-001] correction

**Logged**: 2026-07-27T11:57:26+08:00
**Priority**: high
**Status**: pending
**Area**: frontend

### Summary
截图交接中“新窗口已可见再关闭旧窗口”不能保证视觉连续，透明窗口合成和应用激活仍可能产生单帧闪烁。

### Details
第一轮修复保留选区遮罩直到编辑器窗口置前，消除了抓图期间的裸桌面空档，但用户确认仍有一闪而过的感觉。新日志显示热路径总耗时已降至 50–81 ms，说明剩余问题并非等待时长。当前交接会短暂并存两个各含 42% 黑色遮罩的透明全屏窗口，并调用异步生效的应用激活；窗口“可见”不等于 WindowServer 已在同一帧完成无亮度差的替换。

### Suggested Action
截图选区和编辑状态应优先复用同一个非激活全屏面板或同一个不透明冻结帧表面，避免双透明遮罩叠加和主应用激活。验证必须包含逐帧亮度/窗口层级采样，不能只检查 `isVisible`、日志时长或是否出现裸桌面。

### Metadata
- Source: user_feedback
- Related Files: Sources/MacTools/App/ScreenCapture/ScreenSelectionOverlayController.swift, Sources/MacTools/App/ScreenCapture/ScreenshotEditorPanelController.swift
- Tags: screenshot, windowserver, compositing, flicker, app-activation

---

## [LRN-20260724-002] knowledge_gap

**Logged**: 2026-07-24T17:47:32+08:00
**Priority**: high
**Status**: resolved
**Area**: config

### Summary
identifier-only 自定义 DR 不能让 ad-hoc 构建通过默认 Keychain ACL 获得稳定身份。

### Details
两个构建使用不同 cdhash，但都显示相同 Bundle ID 和 `designated => identifier "local.mactools.mvp"`。构建 A 对新 Keychain 条目选择“始终允许”后，构建 B 仍再次触发 `securityd` Keychain 授权。Apple TN3127 说明 ad-hoc 签名身份与具体代码版本绑定，`SecTrustedApplication` 的受信任应用数据也包含用于唯一识别应用的加密哈希。

### Suggested Action
需要跨构建稳定访问 Keychain 时，必须使用稳定证书身份；如果拒绝证书，只能明确选择较弱的存储边界，不能把固定 Bundle ID 或显示相同的自定义 DR 当作验证证据。

### Metadata
- Source: error
- Related Files: scripts/package_app.sh, Sources/MacTools/App/Sync/KeychainCredentialStore.swift
- Tags: keychain, ad-hoc, code-signing, designated-requirement

### Resolution
- **Resolved**: 2026-07-24T17:47:32+08:00
- **Notes**: 双构建验证失败后撤回实现，并将该方案标记为不可实施。

---

## [LRN-20260714-001] correction

**Logged**: 2026-07-14T19:54:00+08:00
**Priority**: high
**Status**: resolved
**Area**: backend

### Summary
Odd H.264 dimensions were not the cause of AVFoundation `-16122`; incomplete ScreenCaptureKit frames are the supported root-cause direction.

### Details
An independent `AVAssetWriter` probe successfully wrote both `401 × 301` and `400 × 300` H.264 MP4 files. A second probe appended a sample that was valid and data-ready but had no image buffer; it reproduced `AVFoundationErrorDomain -11800` with underlying status `-16122` exactly. Apple’s ScreenCaptureKit sample requires checking for `SCFrameStatus.complete` and a non-nil image buffer before processing a frame, while the recorder previously appended every data-ready sample.

### Suggested Action
Validate ScreenCaptureKit frame status and image-buffer presence before appending to `AVAssetWriter`, and use minimal media probes before assuming encoder dimension restrictions.

### Metadata
- Source: error
- Related Files: Sources/MacTools/App/ScreenCapture/MP4ScreenRecorder.swift
- Tags: avfoundation, screencapturekit, debugging

### Resolution
- **Resolved**: 2026-07-14T19:54:00+08:00
- **Notes**: Replaced the dimension workaround with complete-frame validation.

---

## [LRN-20260724-001] correction

**Logged**: 2026-07-24T17:22:45+08:00
**Priority**: medium
**Status**: resolved
**Area**: config

### Summary
用户期望在首次启动时完成一次凭据授权，而不是延后到首次使用翻译时懒加载。

### Details
最初将“不再每次启动请求密码”解释为启动阶段完全不访问 Keychain，并把授权推迟到翻译入口。用户明确修正为：第一次打开 App 时直接请求并完成一次授权，后续启动不再请求。

### Suggested Action
凭据授权方案应区分“首次安装启动”和“后续普通启动”，在设计触发时机前先确认用户是要延迟授权还是一次性初始化授权。

### Metadata
- Source: user_feedback
- Related Files: Sources/MacTools/App/AppEnvironment.swift
- Tags: keychain, first-launch, credential, authorization

### Resolution
- **Resolved**: 2026-07-24T17:22:45+08:00
- **Notes**: 放弃翻译入口懒加载设计，重新确认首次启动授权和后续启动行为。

---

## [LRN-20260714-002] correction

**Logged**: 2026-07-14T21:00:39+08:00
**Priority**: medium
**Status**: resolved
**Area**: frontend

### Summary
For visual exploration, “similar feeling” means preserve mood and rendering language, not the reference image's subject geometry.

### Details
The requested app-icon follow-up used a translucent ribbon reference. Generating ten new ribbon folds kept the image too similar even though the geometry changed. The correct interpretation is to preserve only the dark restrained background, cyan-blue-violet glass palette, soft glow, premium macOS finish, and single-symbol simplicity while exploring clearly different metaphors and silhouettes.

### Suggested Action
When a user asks for the same feeling, explicitly classify the reference as a mood/material reference, list the retained style attributes, and vary the central object, silhouette, negative space, and metaphor across concepts.

### Metadata
- Source: user_feedback
- Related Files: N/A
- Tags: imagegen, icon-design, visual-reference, concept-diversity

### Resolution
- **Resolved**: 2026-07-14T21:00:39+08:00
- **Notes**: Regenerated the set from ten distinct icon metaphors while retaining only the reference image's visual mood.

---
