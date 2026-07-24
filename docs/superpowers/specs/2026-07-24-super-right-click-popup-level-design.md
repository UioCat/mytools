# 超级右键弹出层置顶设计

## 目标

超级右键面板每次展示时都位于当前交互环境的应用窗口之上，并可进入普通桌面、全屏应用和 Stage Manager 场景。面板继续保持非激活特性，不抢走原应用焦点；点击面板外部仍按现有规则关闭。

## 根因

当前面板使用 `.floating` 层级，只能稳定高于普通 `.normal` 窗口。其他应用的浮动工具窗、模态窗口、状态窗口和菜单层窗口可以位于它上方。

面板的 `collectionBehavior` 仅包含 `.transient` 和 `.ignoresCycle`，没有声明跨桌面空间以及加入其他应用全屏或 Stage Manager 窗口组的能力。`orderFrontRegardless()` 只负责将窗口移到自身层级的最前方，不能补足窗口层级和空间归属策略。

## 方案比较

| 方案 | 优点 | 代价与边界 |
| --- | --- | --- |
| `.popUpMenu` 并补齐空间归属（采用） | 高于普通窗口、浮动工具窗、模态面板和状态窗口；语义接近光标附近的临时操作面板 | 可能短暂覆盖其他应用的普通模态面板；需要保留外部点击关闭，避免持续争抢系统窗口顺序 |
| 保留 `.floating` 并补齐空间归属 | 对系统和其他应用干扰最小 | 其他浮动窗口或更高层级窗口仍可能覆盖超级右键 |
| 使用 `.screenSaver` | 几乎不会被普通界面覆盖 | 会压住菜单、弹窗和关键系统界面，不适合日常操作面板 |

## 当前方案

在 `ContextPanelWindowAppearance` 中集中定义超级右键窗口策略：

- 窗口层级使用 `.popUpMenu`；
- 保留 `.borderless` 和 `.nonactivatingPanel`，展示时不激活 MacTools；
- `collectionBehavior` 包含 `.transient`、`.ignoresCycle`、`.canJoinAllSpaces` 和 `.canJoinAllApplications`；
- 明确保持 `hidesOnDeactivate = false`，避免前台应用状态变化导致面板自动隐藏。

`ContextPanelController` 创建面板时应用一次完整策略。每次 `show` 更新内容和位置后，再重新应用完整策略并调用 `orderFrontRegardless()`，确保复用旧面板时层级和空间行为不会沿用异常运行时状态。

面板展示后不使用定时器或系统通知持续重复置顶。系统菜单、安全授权界面或更高系统层级窗口在之后出现时，仍由 WindowServer 决定顺序，MacTools 不与系统界面持续争抢前台。

## 交互边界

- 点击面板外部继续触发 `orderOut`，这是主动关闭，不属于被窗口覆盖。
- 面板继续不成为 key 或 main window，原应用保持键盘焦点。
- 同一 `.popUpMenu` 层级中，后展示的系统菜单可以排到超级右键之前。
- 其他应用的普通模态面板层级低于 `.popUpMenu`，可能被超级右键短暂覆盖；用户点击外部时超级右键会先关闭。
- 屏保、锁屏、安全授权等更高系统层级不受该策略影响。

## 测试与验证

- 为窗口外观策略增加测试，断言层级为 `.popUpMenu`，并包含跨 Space、全屏和 Stage Manager 所需的 collection behavior。
- 验证策略应用后仍为非激活面板、不会随应用停用而隐藏。
- 运行聚焦测试 `swift test --filter ContextPanelWindowAppearanceTests`，再运行完整 `swift test`。
- 使用 `scripts/rebuild_and_run_app.sh` 构建并启动打包应用。
- 在普通窗口、其他应用浮动窗口、全屏应用和 Stage Manager 下触发超级右键，确认每次展示都位于目标应用窗口上方。
- 打开系统右键菜单并触发外部点击，确认系统菜单可正常展示且超级右键按预期关闭。
- 在明暗背景检查圆角、阴影、键盘焦点和外部点击关闭行为，确认没有标题栏残留、矩形系统阴影或背板层。
- 运行 `git diff --check` 和仓库敏感信息扫描。
