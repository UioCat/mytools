# P3 死代码与文件边界简化设计

## 实施状态

- 状态：已实施并通过自动化验证。
- 验收结果：领域拆分、源码边界测试、完整单元测试、严格并发零告警、打包启动及设置页明暗外观检查已通过。

## 目标

P3 只处理能够证明不改变行为的代码组织问题：删除无读取的参数传播，将大型文件按现有职责边界拆分，并保持所有类型、文案、状态、回调和持久化语义一致。

## 死代码

`confirmCloudAccountSwitch` 从 `AppEnvironment` 经两层运行时视图传到 `SettingsView`，但设置页没有读取、按钮或状态使用该闭包。删除整条传播链，并用源代码测试防止无效入口重新出现。

数据库列、同步协议字段、设置解码默认值和迁移状态即使当前界面没有直接引用，也承担向后兼容职责，不在 P3 删除。

## 文件拆分

### 设置页

保留 `SettingsView.swift` 作为公开入口和页面组合根。现有子类型按领域原样迁移：

| 文件 | 职责 |
| --- | --- |
| `SyncSettingsEditor.swift` | 同步状态、目录、容量、设备与删除确认 |
| `SettingsComponents.swift` | 外观编辑器和通用 section/row 容器 |
| `ClipboardSettingsEditor.swift` | 剪贴板与超级右键设置 |
| `WindowLayoutSettingsEditor.swift` | 窗口模式、快捷键捕获与预览 |
| `TranslationSettingsEditor.swift` | 翻译配置、API Key 原生输入和键盘命令 |
| `PermissionStatusRow.swift` | 普通状态行和权限状态行 |

只把跨文件子类型从 `private` 调整为模块内部可见；成员访问级别和视图结构不变。

### 存储仓储

`ClipboardRepository.swift` 保留剪贴板查询、写入和同步辅助逻辑。载荷垃圾回收器迁移到 `PayloadGarbageCollector.swift`，GRDB 行映射迁移到 `ClipboardItem+FetchableRecord.swift`。SQL、事务范围和异常类型保持不变。

### 应用环境

`AppEnvironment.swift` 保留依赖装配和运行时业务协调。剪贴板轮询、启动维护和自动粘贴激活工作器迁移到 `AppEnvironmentWorkers.swift`；工作器仍保持原 Actor/主 Actor 隔离。

## 验证

- 更新读取固定源文件的契约测试，并增加文件边界测试。
- 运行设置、仓储、启动和死代码聚焦测试。
- 运行完整 `swift test` 与严格并发测试，要求 Sources 和 Tests 继续零告警。
- 重新打包并启动应用，检查设置页、菜单栏和进程状态；双机同步由人工环境验证。
