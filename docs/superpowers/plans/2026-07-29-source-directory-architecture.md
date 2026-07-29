# 源码目录架构优化实施计划

## 目标

在不改变 SwiftPM Target、公开 API 和运行时行为的前提下，完成生产源码目录重组，并使当前 108 个
生产 Swift 文件继续满足中文文件、类型、方法和核心逻辑注释规范。

## 基线

- 基线提交：`2365851729dd5650eff74fd4eb834931597376ff`
- 工作分支：`main`
- 生产 Swift 文件：108 个
- 方法声明静态扫描：约 1050 个
- 缺少方法文档注释：28 个
- 缺少文件级注释：0 个

## 实施步骤

### 1. 重组 `MacTools`

- 将入口、生命周期、依赖装配、菜单栏和运行时视图移动到 `Application/`。
- 将剪贴板面板状态和超级右键展示协调移动到 `Features/`。
- 将截图、同步、语音和窗口布局系统实现移动到 `Platform/`。
- 不修改生产 Swift 文件正文。

### 2. 重组 `MacToolsCore/UI`

- 将通用视觉组件移动到 `UI/DesignSystem/`。
- 将主工作台移动到 `UI/Workspace/`。
- 将剪贴板、翻译、设置和超级右键视图按功能聚合。
- 保持 `Panels/` 和非 UI 业务目录不变。

### 3. 更新当前路径引用和边界守卫

- 更新 `Tests/MacToolsCoreTests` 中读取生产源码的固定路径。
- 更新 `AGENTS.md` 和 `README.md` 中代表当前实现的路径。
- 历史 specs 和 plans 保留旧路径。
- 在 `CodeOrganizationSourceTests` 中递归扫描 `MacToolsCore/UI`，禁止导入 GRDB 或引用具体存储实现。

### 4. 完成注释审计

- 为静态扫描识别的 28 个未注释方法补充中文 `///`。
- 移动文件后再次扫描全部 `func/init/deinit/subscript`，要求遗漏清单为空。
- 复核应用装配、存储、同步、凭据、权限、超级右键和截图录屏核心路径。
- 将核心路径中仅复述方法名的注释改写为目的、顺序、不变量、副作用或降级语义。
- 不为普通赋值和显而易见的条件逐行添加注释。

### 5. 验证

依次执行：

```sh
swift test --filter CodeOrganizationSourceTests
swift test --filter AppEnvironmentStartupSourceTests
swift test --filter ScreenshotPresentationSourceTests
swift test --filter ICloudDriveSyncCoordinatorSourceTests
swift test
swift build --product MacTools
scripts/package_app.sh
git diff --check
```

重新执行文件、类型和方法注释扫描，并检查当前源码、测试、脚本和说明中不存在已迁移的活动旧路径。
最后执行敏感字段扫描，只允许字段名、类型名、公开协议说明和测试占位值。

## 变更边界

- 生产代码只允许文件移动和注释变化。
- 测试只允许路径更新和新增源码边界守卫。
- 文档只更新当前结构说明、设计状态和本实施计划。
- 任何非注释生产代码差异都视为阻断问题。
