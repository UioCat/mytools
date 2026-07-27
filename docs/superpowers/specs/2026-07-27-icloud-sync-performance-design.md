# iCloud 同步性能与生命周期治理设计

## 背景

当前同步周期每 30 秒运行一次，稳定周期仍可能读取并哈希全部本地图片、递归同步根目录、扫描凭据副本。关闭同步或切换目录只能淘汰定时任务，不能淘汰已经运行的周期。目录首次准备还在 MainActor 同步执行。

优化目标是在不改变现有 iCloud 文件协议和多设备收敛语义的前提下，让稳定周期只处理轻量元数据，并把内容读取限制在真正需要上传、修复或应用的对象。

## 必须保持的协议语义

- 远端墓碑先应用，本地状态随后重新导出。
- revision 文件先完整写入，manifest 最后原子发布。
- 每台设备只写自己的 replica。
- receipt 绑定设备、generation、revision 和 manifest digest。
- 任一 replica 不完整时暂停对象 GC。
- removal marker 和 reset marker 保持长期有效。
- 同步失败不影响本地剪贴板使用。

## 目标执行流

1. Coordinator 创建包含 epoch 和 rootURL 的同步 lease。
2. Runner 读取协议、reset、removal marker 和轻量 manifest。
3. 从缓存复用未变化的 snapshot 与 inventory。
4. 第一次导出本地记录元数据，不读取图片。
5. 应用远端墓碑。
6. 第二次导出本地记录元数据。
7. 合并本地与远端候选并执行 retention decision。
8. 按 contentID 逐个读取和应用保留的远端内容。
9. 仅在需要发布 revision 时逐个物化缺失或损坏的本地内容。
10. 写入 snapshot，最后发布 manifest。
11. 使用写入 delta 更新 inventory，执行保守 GC。
12. Coordinator 校验 lease 后发布状态。

## 本地导出模型

新增不参与远端编码的 `SyncExportDraft`、`SyncContentDescriptor` 和 `SyncContentSource`。

`SyncExportDraft` 保存 clipboard、preferences、tombstones、outbox cutoff 和内容描述符，不保存内容 `Data`。描述符包含 contentID、kind、准确或保守的存储字节数，以及文本或本地 payload URL。

`ClipboardRepository` 新增同步专用查询，在 SQL 层过滤可同步类型和收藏范围，并 JOIN `payload_objects` 返回 byteCount、relativePath 和 localState。不再使用面向 UI 的无界 `search`。

图片导出阶段只检查 payload 路径、文件存在性和字节数。完整 PNG 与 SHA-256 校验推迟到上传或修复前。文本只在真正写入时编码。

## 内容解析与应用

内容解析器按以下优先级查找内容：

1. 本地 export descriptor。
2. iCloud 共享对象。

每次只物化一个 contentID。远端 replica 的记录先按 contentID 分组，读取一个对象后应用所有引用记录，再释放 `Data`。对象缺失、未下载或损坏时，该 replica 不写 receipt。

容量决策使用本地 descriptor 字节数、inventory 字节数或对象文件 stat。无法取得字节数的对象不会按 0 处理，而是进入 unavailable/deferred 状态。

## 惰性云端写入

`DriveSyncStore.write` 接受 draft、最终内容 ID 集合和 content provider。共享对象缺失或已知损坏时才调用 provider。每个对象写入前和 manifest 发布前检查 cancellation。

写入结果包含 manifest、实际上传/修复的 contentID，以及 inventory delta。Runner 使用 delta 更新已有 inventory，不再在写入后递归扫描。

manifest 仍然是唯一发布点。取消发生在 snapshot 写入后、manifest 发布前时，残留 revision 不可见，后续写入会清理。

## 凭据同步

凭据扫描结果已经包含当前设备副本。winner 与当前副本 envelope 完全相同时不写；缺失、损坏或落后时才写。未下载和显式文件冲突继续报告，不直接覆盖。

`CredentialSyncResult` 增加 `didWriteReplica`，用于确定性测试。

启动流程合并为一次“凭据优先的完整同步”：先完成并发布凭据对账结果，再运行剪贴板同步，本轮不重复对账。期间若凭据再次更新，由正常补跑处理。

## 生命周期与取消

Coordinator 维护单调递增 epoch。开启、关闭、切换目录和影响同步结果的配置变化都会使旧 lease 失效。

Runner 在以下边界检查 cancellation：

- 开始远端扫描前；
- 应用墓碑和远端记录前；
- 写 eviction、content、snapshot、manifest、reset 和 removal marker 前；
- 更新本地 receipt/revision 前。

所有状态、设备、设置和凭据 handler 发布前再次校验 lease。过期周期返回 cancellation，不展示为失败，也不能覆盖 `.off`。

已经进入的单次同步文件 API 不能被外部强制中断，但关闭后不会开始下一项写入，且旧 manifest 和 UI 结果不会发布。

## Inventory 与 Replica 缓存

Runner 持有按 storeID 隔离的进程内观察缓存：

- 当前 inventory；
- 以 manifest digest 为键的设备 snapshot；
- 上次完整审计时间。

稳定周期只读取 manifest 小文件。digest 未变化时复用 snapshot；变化时才读取对应 revision。写入和 GC 通过 delta 更新缓存。

第一次运行、storeID/rootURL 变化、缓存不一致、接近容量上限或超过审计周期时，重新扫描 `objects/text/sha256` 与 `objects/images/sha256`。缓存失效只影响性能，不影响重建后的正确性。

## 设备移除清理

移除设备采用本地可恢复状态：

1. 当前设备保存获胜凭据。
2. rehome 被移除设备的未压缩墓碑。
3. 写 removal marker。
4. 强制发布包含接管状态的当前设备 revision。
5. 发布成功后删除被移除设备的 replica、eviction 和 credential replica。

removal marker 永久保留。reset marker 默认保留，因为它可能是最高 generation 的唯一证据。共享对象不按设备直接删除，只通过引用关系和稳定窗口 GC。

## 同步目录准备

`NSOpenPanel` 保持在 MainActor。用户选择完成后，专用 utility 串行 worker 负责 security-scoped access、`DriveSyncStore.prepare`、bookmark 和数据库持久化。

MainActor 维护选择 generation，只应用最新结果。准备失败保留原目录；第二次选择会淘汰第一次结果。异步准备期间展示明确状态，不把正常等待报告为同步失败。

## 可观测性

测试和 Debug 诊断只记录操作计数：

- 本地内容物化数和读取字节数；
- 内容哈希次数；
- replica snapshot 读取次数；
- 完整 inventory 扫描次数；
- 凭据副本写入次数。

不得记录剪贴板内容、contentID、真实文件路径或凭据。

## 验收标准

- 稳定周期本地图片读取、图片哈希、凭据写入和完整 inventory 扫描均为 0。
- 容量淘汰内容不会被物化。
- 同时存活的图片内容与单对象上限同阶，不随总同步容量增长。
- manifest 未变化时不读取 snapshot。
- 关闭同步后最终状态保持 `.off`，旧周期不再发布。
- 切换目录后旧 root 的结果失效。
- 目录准备期间 MainActor 保持响应。
- 多设备墓碑、receipt、reset、移除设备与 GC 测试保持通过。

## 验证

先运行受影响模块的聚焦测试，再运行 `swift test`。iCloud、安全作用域、关闭同步竞态和目录切换必须使用打包应用验证；`swift run MacTools` 不能作为这些场景的证据。
