# MacTools 代码优化审查与建议

## 审查基线与结论边界

审查对象为 `d7f5eddf157ded6837b547aa01014626a145103d`，覆盖应用装配、核心服务、平台适配、UI、测试、打包与发布链路。以下保留扫描基线与建议，当前实现和验证状态见[修复记录](optimization-fixes-2026-10-02.md)。

| 证据 | 结果与边界 |
| --- | --- |
| `swift test` | 751 项测试，0 失败，1 项 WindowServer 集成测试按默认规则跳过；退出状态为 0 |
| 严格并发构建 | `swift build --product MacTools -Xswiftc -strict-concurrency=complete -Xswiftc -warn-concurrency` 通过，无编译警告 |
| 环境 | macOS 26.5.1、Apple Swift 6.3.2、arm64 |
| 新发现 | P2 表示代码或上游公告支持的条件性缺口；新增触发场景尚未执行回归复现，不能视为已修复或运行时验证通过 |
| 性能建议 | 没有采集启动、CPU、内存或 UI 追踪；收益待测量，不能仅凭同步调用或文件长度推断当前用户已遇到卡顿 |

优先处理受影响依赖、文件覆盖风险和异步操作归属，再补齐快捷键与数据访问的一致性。现有仅收藏同步、长短按互斥、静态截图、Retina/IME 排版及面板圆角保护应继续保留。

## 模块建议

| 模块 | 优先优化方向 | 已有保护或边界 | 主要代码位置 |
| --- | --- | --- | --- |
| 应用装配与生命周期 | 异步保存只合并本次字段；凭据失败回调也核对代际 | 凭据 I/O 已隔离，启动迁移耗时待测量 | [AppEnvironment.swift](../Sources/MacTools/Application/AppEnvironment.swift#L437)、[凭据接线](../Sources/MacTools/Application/AppEnvironment+Credentials.swift#L98) |
| 剪贴板与自动粘贴 | 查询先筛选再分页；粘贴前核验当前目标和操作身份 | 空闲采样、后台解码与下采样已实现 | [ClipboardPanelModel.swift](../Sources/MacTools/Features/Clipboard/ClipboardPanelModel.swift#L40)、[PasteActivationAttempt](../Sources/MacTools/Application/AppEnvironmentWorkers.swift#L378) |
| 本地存储与迁移 | 接入本地字节预算；文件创建与引用建立共用锁区间 | 收藏/置顶保护、事务 GC 与迁移回退已有测试 | [ClipboardRepository.swift](../Sources/MacToolsCore/Storage/ClipboardRepository.swift#L264)、[展示索引](../Sources/MacToolsCore/Storage/ClipboardDatabase.swift#L93) |
| iCloud 同步 | 管理动作重试绑定原目录；评估大目录回收推进 | PNG 竞态只造成可恢复的导入失败，不能称永久丢失 | [ICloudDriveSyncCoordinator.swift](../Sources/MacTools/Platform/Sync/ICloudDriveSyncCoordinator.swift#L252)、[PNG 导入](../Sources/MacToolsCore/Sync/SyncLocalRepository.swift#L551) |
| 设置与凭据 | 入站偏好过滤敏感字段；异常整数受控失败；补真实旧 JSON 脱敏测试 | AES-GCM、私有权限、墓碑和回声保护已存在 | [PreferenceRepository.swift](../Sources/MacToolsCore/Settings/PreferenceRepository.swift#L167)、[缓存值规范化](../Sources/MacToolsCore/Settings/AppSettings.swift#L219) |
| 超级右键与 Finder | 排他新建文件；文件动作后台执行并展示结果 | 长短按、tap 生命周期与迟到结果已有保护；首次授权交互待实测 | [FileActionService.swift](../Sources/MacToolsCore/FileActions/FileActionService.swift#L79)、[动作接线](../Sources/MacTools/Features/SuperRightClick/ContextPanelController.swift#L396) |
| 截图录屏 | 导出结果校验会话；录制器启动、停止和帧回调统一资源归属 | 冻结弹窗、像素坐标、中文组合态和 PNG 排版已修复 | [截图完成接线](../Sources/MacTools/Platform/ScreenCapture/ScreenCaptureCoordinator.swift#L192)、[MP4ScreenRecorder.swift](../Sources/MacTools/Platform/ScreenCapture/MP4ScreenRecorder.swift#L43) |
| 翻译与朗读 | 组合态 Return 先交原生输入；明确请求和朗读取消规则 | 当前模型为 `qwen-mt-flash`；并发重复提交已受限 | [RuntimeViews.swift](../Sources/MacTools/Application/RuntimeViews.swift#L882)、[HTTP 错误](../Sources/MacToolsCore/Translation/BailianTranslationProvider.swift#L116) |
| 窗口布局与快捷键 | 捕获/注册共用键表；传播失败并保留旧绑定；编辑保留其他绑定 | 十四种布局、80% 宽填高居中、跨屏与旧默认迁移已实现 | [HotKeyService.swift](../Sources/MacToolsCore/HotKeys/HotKeyService.swift#L31)、[多绑定替换](../Sources/MacToolsCore/WindowLayout/WindowLayout.swift#L337) |
| 权限与登录项 | 首次监听失败后接入授权恢复；权限整理防重复执行 | 登录项 `.notFound` 注册和失败重试已有覆盖；同进程权限恢复待系统验证 | [权限刷新](../Sources/MacTools/Application/RuntimeViews.swift#L404)、[PermissionResetActionView.swift](../Sources/MacToolsCore/UI/Settings/PermissionResetActionView.swift#L38) |
| 共用工作台与面板 | 外观草稿跟随隐藏期间的更新；测量根观察范围 | 无边框、透明外沿、AppKit 圆角裁切和显示周期缩放已实现；视觉未实测 | [SettingsView.swift](../Sources/MacToolsCore/UI/Settings/SettingsView.swift#L139)、[工作台观察](../Sources/MacTools/Application/RuntimeViews.swift#L64) |
| 更新、打包与依赖 | 定向升级 Sparkle；核对随包许可证；区分更新不可用与检查中 | 签名与资产验证已有保护；实际产物和更新安装未验证 | [Package.resolved](../Package.resolved#L19)、[更新状态](../Sources/MacTools/Platform/Updates/SystemUpdateService.swift#L19) |

## 优先修复方案

成本按改动范围与验证难度区分：小为单入口或局部决策，中为跨模块状态或系统行为，大为协议或生命周期重构；不代表已承诺的工期。

### 依赖、文件与设置安全

| 项目 | 触发条件与影响 | 最小方案与主要风险 | 成本 | 验收 |
| --- | --- | --- | --- | --- |
| P2 · Sparkle 受影响依赖 | 锁定 2.9.5 落入上游安装器路径竞争公告范围；MacTools 可利用性未复现 | 定向更新 Sparkle 至经验证的已修复版本，最低 2.9.6；保持 GRDB 不变。风险在嵌入组件、签名与真实更新安装 | 中 | 锁文件与实际框架版本一致；执行[发布指南](release-guide.md)中依赖及更新链路变化的条件验证 |
| P2 · 新建文件覆盖 | 同名文件在检查后、创建前出现，可能被空内容覆盖 | 排他创建时同时指定 `O_CREAT` 和 `O_EXCL`；只在 `EEXIST` 时尝试下一个名称，保留现有命名与权限 | 小 | 注入竞争创建，竞争文件内容不变；名称冲突和不可写目录均有回归 |
| P2 · 同步重试目录漂移 | 原目录锁忙后切换目录，延迟重试重新读取配置，对新目录重置或移除设备 | 重试持续持有原配置与 lease，过期直接结束；避免只检查后又重新读取配置。重置推进协议代际，并非直接删除共享对象 | 小 | 临时 A/B 目录及假调度器验证 B 无意外标记或删除；原目录不变时重试可完成 |
| P2 · 同步 PNG 清理竞态 | PNG 已写但引用未建立，启动维护将其当孤儿删除，导入失败并重试 | 复用仓储原子入口，保持 `PayloadStore → database` 锁序、确定性 UUID 合并和新对象失败清理 | 小至中 | 屏障交错验证清理等待引用提交；失败不确认 receipt，不删除已有对象 |
| P2 · 远端异常字段与整数 | 入站 `translation.apiKey` 可进入 SQLite 并再导出；异常缓存值或时钟极值可溢出 | 入站值与 clocks 共用敏感字段边界；规范化前夹紧数值，时钟溢出返回错误。未知非敏感字段兼容策略须保留 | 小至中 | 旧/异常 JSON 经真实解码和合并入口；原始存储及导出无凭据字段，极值不崩溃且事务不污染 |

Sparkle 的官方公告 [GHSA-3x7w-j75x-ppq5](https://github.com/sparkle-project/Sparkle/security/advisories/GHSA-3x7w-j75x-ppq5) 于 2026-08-17 公布，标明受影响版本 `<= 2.9.5`、修复版本 `2.9.6`；2026-10-01 已核对。另一公告 [GHSA-4v99-qgq9-6pxp](https://github.com/sparkle-project/Sparkle/security/advisories/GHSA-4v99-qgq9-6pxp) 要求宿主本身以 root 运行，普通用户运行 MacTools 未证实满足条件。新建文件覆盖语义已核对 [Apple FileManager 文档](https://developer.apple.com/documentation/foundation/filemanager/createfile(atpath:contents:attributes:))。

入站敏感字段问题限定于异常或旧远端输入，受支持旧客户端是否产生该格式待确认；没有证据证明当前本机新凭据已泄露。固定凭据派生材料属于公开协议常量，继续以本地和同步目录权限作为访问边界。

### 异步操作归属

| 项目 | 触发条件与影响 | 最小方案与主要风险 | 成本 | 验收 |
| --- | --- | --- | --- | --- |
| P2 · 翻译设置旧快照 | API Key 保存跨 `await`，随后整份设置回写覆盖期间的新配置 | 等待后基于最新设置合并本次字段；同类保存定义代际/顺序；失败回调同样校验加载代际 | 中 | 暂停凭据保存，交错本地/远端更新及旧加载失败，验证其他类别与新凭据状态不回退 |
| P2 · 取消后 PNG 导出 | Escape 取消后旧导出仍可写剪贴板，甚至关闭新截图会话 | 完成副作用前校验会话和编辑状态；保存任务句柄并检查取消，不能仅依赖取消编码任务 | 小 | A 导出暂停 → 取消 → 打开 B → 完成 A；无旧写入且 B 保持可操作 |
| P2 · 录屏资源交错 | 启动尚未完成即取消重开，共享 recorder 的旧启动/收尾可能影响新会话 | await 前预留启动状态，资源统一隔离；启动/停止及帧回调使用身份，清理完成前维持互斥 | 中 | 可暂停采集源与 stream；任意交错最多一个活跃资源，旧任务只清理自己的文件 |
| P2 · 粘贴目标失效 | 激活后的延迟或超时回退期间焦点切换，全局 Command+V 发给当前其他应用 | 所有延迟共用可取消尝试；发送前核验目标存活、前台 PID 和操作身份 | 中 | 假时钟覆盖目标退出、激活失败、焦点切换、重开面板；有效尝试只发一次 |

### 输入、设置与记录访问

| 项目 | 触发条件与影响 | 最小方案与主要风险 | 成本 | 验收 |
| --- | --- | --- | --- | --- |
| P2 · 快捷键一致性 | 注册失败被吞掉且旧键已注销；不支持的字符仍可保存；主绑定编辑删除其他绑定 | 捕获/注册共用支持表；按项注册并传播失败、恢复旧键；按绑定编辑，保留其他项 | 中 | 抛错注册器与 `[A, B] → [C, B]` 回归；保存、持久化、运行时结果一致 |
| P2 · 1000 条截断 | 收藏与置顶可超过普通历史上限；先截断再筛选使旧收藏、标签和搜索不可访问 | 先按类别/标签/搜索筛选再分页；全库汇总单独查询，保持稳定排序和选中项 | 中 | 501 个旧收藏 + 500 条新普通历史，最旧项通过收藏、唯一文本及专属标签可访问 |
| P2 · 翻译组合态 Return | marked text 的 Return 若进入自定义 `keyDown`，会先提交并吞掉原生确认 | 组合态优先交原生事件处理；非组合态保留提交、换行与编辑命令 | 小 | 原生 `setMarkedText` + Return 决策测试；真实中文输入法确认，保持 `TEXT-EDIT-001` |
| P2 · 授权恢复接线 | 首次监听安装失败，后续权限显示可用却未触发重装 | 权限由不可用转可用且监听缺失时重试；有效监听不因普通激活重启 | 中 | 注入 checker/工厂验证恢复与撤销；打包验证同进程恢复及系统要求重启的分支 |
| P2 · 隐藏外观草稿 | 非通用分类期间远端更新外观，返回后选择器仍显示旧值 | 在草稿持有者同步或直接读取当前值，保留失败回滚；避免重建全部设置页清空其他草稿 | 小 | 同一 SwiftUI 宿主隐藏更新再返回，显示与实际设置一致，其他未保存编辑不丢失 |

## 资源边界与性能实验

### 有明确边界缺口的资源策略

| 项目 | 当前问题与方案 | 成本与验收 |
| --- | --- | --- |
| P2 · 持久化积压 | `.unbounded` 队列遇持续失败会永久重试队首；在生产端同步准入，预算覆盖待处理和处理中载荷，增加错误分类、退避和可见暂停状态。不能把积压转移成无界入队 Task，或静默丢弃最旧记录 | 中；合成大载荷与失败/恢复注入，预算有界、已接受记录有序、停止可取消 |
| P2 · 本地容量 | `maxCacheMegabytes` 未接入运行时，只按普通历史条数裁剪；按唯一 payload 占用回收普通项并复用事务 GC | 中；去重不重复计费，收藏/置顶保留，减少容量立即处理；受保护内容超额行为待确认 |
| P3 · 日志保留 | 内存记录、待写闭包和单文件都需预算；改为有限消息缓冲、有界写入批次与按大小轮换，维持 0700/0600 和有序写入 | 小至中；临时目录测试保留窗口、待写积压、总占用、轮换顺序和权限，错误信息不暴露用户路径 |

### 先测量再决定的优化

| 实验 | 合成输入与指标 | 候选方案与约束 |
| --- | --- | --- |
| 消费积压与日志 | 合成大载荷，控制慢消费、持续失败和恢复；已接受/待处理字节、驻留时间、RSS、重试与日志待写占用 | 缺口已明确，实验用于选择预算/退避并检验端到端有界；暂停须可见，恢复后已接受记录保序 |
| 查询与图片处理 | 500/5000/50000 条数据、重复 4K/8K PNG；查询计划、首屏耗时、读取与解码量 | 展示索引补 `lastCapturedAt`，采用新迁移；摘要一致后减少已校验 PNG 二次解码。保留中文子串搜索和损坏修复 |
| 主线程 I/O 与启动 | 延迟文件系统、AX 替身、设置写竞争和合成旧 Store；逐项测调用 p50/p95/p99、交互响应与菜单可操作时点 | 测出阻塞再逐项后台化，保持迁移回退与字段合并；回主线程前校验身份，0.5 秒回读策略不等于 AX IPC 超时 |
| 同步回收规模 | 257+ 有效快照、1k/10k revision、慢枚举；推进率、枚举/排序/证明耗时 | 超预算当前保守保留；仅在完整一致证明成立后分批推进，容量缓存不能作为删除证明 |
| 工作台刷新 | 固定页面和内容，仅推进其他服务状态；body 更新、资源加载与主线程时间 | 静态图标一次注入，收窄叶模块观察；不盲目替换观察框架或加 `.equatable()` |
| 多屏冻结帧 | 合成多屏 4K 图案重复编辑/取消；选区、编辑、结束时驻留内存和窗口数 | 成功交接后释放非选中屏图像，保留选中冻结背景与临时弹窗语义；引用重复不等于像素复制 |

所有性能对照使用同机、同构建模式、相同数据和操作；记录原始指标，不在行为测试中依赖机器耗时阈值，也不预设收益百分比。

## 维护建议与待确认项

| 范围 | 当前方案或待确认事项 | 原因与影响 |
| --- | --- | --- |
| 截图编辑器 | 仅按已有原生文本/预览组件边界拆文件 | 降低审查成本，保持状态所有权和焦点；文件长度不构成性能证据 |
| 翻译 | 请求保存取消句柄、区分取消与错误、补 HTTP 异常矩阵；超级右键关闭是否停朗读待确认 | 主工作台重复提交已有保护；没有依据断言旧译文覆盖新请求或服务端已泄露凭据 |
| 凭据测试 | 用确实含占位明文的旧 JSON 验证脱敏 | 当前测试经新编码器生成输入时已排除 API Key，不能证明擦除分支 |
| 权限 | 整理期间展示执行状态并在运行时合并重复请求 | 维持现有确认，不增加自动重置权限 |
| 更新与许可 | 不可用与检查中分开；核对最终包中的 GRDB/Sparkle 许可资源 | 开发包不应永久显示进度；实际随包许可待产物核验，不据脚本猜测所有许可均缺失 |
| 数据预算 | 收藏/置顶已超本地容量时，新图片拒绝、保留或提示方式待确认；故障暂停期间的复制遗漏提示待确认 | 不能以自动删除受保护内容或静默丢弃快照满足预算 |
| 首次 Finder 授权 | 授权确认点击是否进入全局外部点击监听待实测 | 若复现需建模授权等待，不能直接移除已有捕获取消保护 |

## 推荐实施顺序

| 顺序 | 优化内容 | 拆分与前置条件 |
| --- | --- | --- |
| 1 | Sparkle 定向修复、排他文件创建、入站偏好过滤 | 各自独立提交；依赖升级按发布指南验证，字段过滤保持未知正常字段兼容 |
| 2 | 同步管理 lease、PNG 锁、设置合并、截图导出、录屏资源和粘贴目标 | 各问题先有确定性失败回归；截图导出小修与录屏状态改造分开，不混入编辑器拆分 |
| 3 | 快捷键一致性、组合态输入、权限恢复、隐藏外观及全库分页 | 查询/汇总接口先于分页 UI；保留键盘导航和现有设置迁移 |
| 4 | 有界消费与日志、本地容量策略 | 预算和暂停行为先明确；共用存储裁剪入口，不能删除受保护内容 |
| 5 | 经测量成立的性能优化与组件整理 | 索引使用新迁移；线程改造先有身份保护；回收缓存必须证明一致，结构整理单独验证 |

## 验证与实施约束

每个缺陷先建立能失败的回归，再实施最小改动；异步使用可控 continuation、时钟和资源替身，存储使用临时目录/数据库。关键场景映射如下，完整标准以[人工验证清单](manual-verification.md)为准。

| 改动 | 聚焦测试入口 | 重点场景 |
| --- | --- | --- |
| 同步管理、PNG、范围与回收 | `ICloudSyncSchedulingTests`、`SyncLocalRepositoryTests`、`ClipboardRepositoryTests` 及相关同步测试 | `SYNC-SCHEDULE-001`、`SYNC-RECOVERY-001`、`SYNC-FAVORITES-001`、`SYNC-IDLE-PERF-001`，按实际影响选择 |
| 设置与凭据合并 | `SettingsStoreTests`、`CredentialAccessCoordinatorTests`、`SyncLocalRepositoryTests`；新增应用层交错保存测试 | `SYNC-CONVERGENCE-001`、`PANEL-FOCUS-001`；并行保存须新增稳定场景 |
| 消费与本地容量 | `ClipboardServiceTests`、`ClipboardRepositoryTests`；新增消费工作器故障恢复测试 | `CLIPBOARD-IDLE-001` 与剪贴板功能检查；容量/故障预算须新增稳定场景 |
| 截图导出与录屏生命周期 | `ScreenshotEditorInteractionTests`、`ScreenshotRendererTests`；新增协调器与录制器行为测试 | `CAPTURE-POPUP-001` 取消/重开及截图录屏功能检查；文字相关再执行两项文字场景 |
| 快捷键、粘贴、翻译输入 | `HotKeyServiceTests`、`PasteActionServiceTests`、`TranslationInputKeyCommandTests`；新增应用层目标与原生输入测试 | `WINDOW-LAYOUT-001`、`WINDOW-LAYOUT-002`、`TEXT-EDIT-001`、`PANEL-FOCUS-001` 与自动粘贴功能检查 |
| 右键文件动作、权限恢复 | `FileActionServiceTests`、`SuperRightClickMonitorTests`、`PermissionServiceTests` | `RIGHT-CLICK-001`、`RIGHT-CLICK-002` 与 Finder 授权/撤销、文件动作检查；登录项变更才追加 `LOGIN-ITEM-001` |
| 工作台、共用窗口、DesignSystem | `SettingsNavigationTests`、`MainPanelControllerTests`、`MainWorkspaceTests` | 清单规定的全部六项共用面板场景，覆盖明暗背景、缩放、焦点、外部点击和键盘 |
| 更新依赖或发布链路 | `PackageAppScriptTests`、`SoftwareUpdateSettingsTests`、`ReleaseWorkflowSourceTests` 等 | 仅遵循[发布指南](release-guide.md)相应条件验证；不另建标签或发布步骤 |

实现验证先运行受影响测试类，再执行 `swift test --parallel --num-workers 4`；涉及 Task、Actor、Timer 或共享状态时追加严格并发构建。涉及 UI 和系统能力时使用打包应用，不以源码字符串断言或进程启动替代真实结果。新增发现的自动化复现、实际系统权限恢复、真实输入法、签名产物、更新安装和性能指标目前均待验证。
