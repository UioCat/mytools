# MacTools 本地加密与 iCloud 凭据同步实施计划

**目标：** 将百炼 API Key 从持续访问 Keychain 改为本地 AES-GCM 加密缓存，并通过现有
iCloud Drive 同步目录在多台 Mac 间恢复；旧 Keychain 只在首次升级启动时作为只读迁移源。

**架构：** 在 `MacToolsCore` 中实现版本化加密信封、原子文件存储、设备 replica 和逻辑时钟
合并；在 App 目标中保留 Security.framework 只读适配器，并把凭据对账接入现有
`ICloudDriveSyncCoordinator` 后台文件协调流程。`AppEnvironment.start()` 先尝试本地/云端，
只有两者都没有记录时才立即触发旧 Keychain 迁移。

**技术栈：** Swift 5.10、CryptoKit、Foundation、Security.framework、Swift Package Manager、
XCTest、macOS 26+

## 全局约束

- v1 固定使用 HKDF-SHA256 派生 32 字节密钥和 AES-256-GCM，不实现算法自动降级。
- 派生材料是公开协议常量，不提交随机私钥或把它描述成真正秘密。
- 本地目录权限为 `0700`，信封和迁移标记为 `0600`；iCloud 权限不作为安全边界。
- 普通设置、SQLite、剪贴板快照、日志和错误信息不得包含百炼凭据。
- 旧 Keychain 适配器只查询，不保存、更新或删除任何项目。
- 本地有效凭据不因 iCloud 未下载、目录失效或同步关闭而不可用。
- 空值保存生成带更高逻辑时钟的加密删除标记，不能直接移除文件。
- 不删除实验阶段留下的 Keychain v2 项目。
- 文件 I/O、Keychain 查询和 iCloud 协调不阻塞 Main Actor。

---

### 任务 1：实现版本化 AES-GCM 加密信封

**文件：**

- 新增：`Sources/MacToolsCore/Settings/CredentialEnvelope.swift`
- 新增：`Tests/MacToolsCoreTests/CredentialEnvelopeCodecTests.swift`

**接口：**

- `CredentialEnvelope`：保存 schema、key version、credential ID、逻辑时钟和 combined
  sealed box。
- `CredentialEnvelopeRecord`：保存已认证的 `active` 或 `deleted` 载荷。
- `CredentialEnvelopeCodec`：负责 HKDF 派生、规范 AAD、密封、打开和 JSON 编解码。

- [ ] 先添加失败测试，覆盖 active/deleted 往返、随机 nonce、错误 credential ID、错误
  schema/key version，以及修改头、密文和认证标签后的拒绝行为。
- [ ] 运行：

  ```sh
  swift test --filter CredentialEnvelopeCodecTests
  ```

  预期首次失败，因为 codec 尚不存在。
- [ ] 使用固定 v1 HKDF 标签、`.sortedKeys` 头编码和 `AES.GCM.SealedBox(combined:)` 完成最小
  实现；错误只暴露类型和版本，不携带输入数据。
- [ ] 重新运行相同测试，预期全部通过。

---

### 任务 2：实现本地原子加密存储

**文件：**

- 修改：`Sources/MacToolsCore/Storage/MacToolsStorePaths.swift`
- 新增：`Sources/MacToolsCore/Settings/EncryptedCredentialStore.swift`
- 新增：`Tests/MacToolsCoreTests/EncryptedCredentialStoreTests.swift`
- 修改：`Tests/MacToolsCoreTests/UnifiedStoreBootstrapperTests.swift`

**接口：**

- `MacToolsStorePaths.credentialsDirectory`
- `MacToolsStorePaths.bailianCredentialURL`
- `MacToolsStorePaths.credentialMigrationMarkerURL`
- `EncryptedCredentialStore`：串行读取、写入、合并信封和维护迁移标记。

- [ ] 添加失败测试，覆盖路径、首次无文件、原子写入、写后读回、目录 `0700`、文件 `0600`、
  损坏文件、迁移标记和 tombstone 保留。
- [ ] 通过可注入文件系统失败点证明写入失败时旧信封不变。
- [ ] 运行：

  ```sh
  swift test --filter 'EncryptedCredentialStoreTests|UnifiedStoreBootstrapperTests'
  ```

  预期首次失败。
- [ ] 实现最小文件存储；所有更新在同一锁内完成，并在替换后重新设置权限和读回校验。
- [ ] 重新运行相同测试，预期全部通过。

---

### 任务 3：实现 iCloud 凭据 replica 与冲突收敛

**文件：**

- 新增：`Sources/MacToolsCore/Sync/CredentialReplicaStore.swift`
- 新增：`Sources/MacToolsCore/Sync/CredentialReconciler.swift`
- 新增：`Tests/MacToolsCoreTests/CredentialReplicaStoreTests.swift`
- 新增：`Tests/MacToolsCoreTests/CredentialReconcilerTests.swift`
- 修改：`Tests/MacToolsCoreTests/DriveSyncStoreTests.swift`

**接口：**

- `CredentialReplicaStore(rootURL:)`：读写
  `credentials/replicas/<deviceID>.v1.json`。
- `CredentialReconciler.winner(...)`：复用 `ClipboardFieldClock.wins(over:)`。
- `DriveSyncStore.removedDeviceIDs(generation:)`：为凭据扫描提供已移除设备集合。

- [ ] 添加失败测试，覆盖每设备单写、未下载文件、相同/不同冲突版本、损坏副本隔离、设备 ID
  文件名校验和 removed-device 过滤。
- [ ] 添加两个隔离本地客户端共享临时同步根目录的测试，覆盖并发 active、删除胜出、防止旧值
  复活和最终收敛。
- [ ] 运行：

  ```sh
  swift test --filter 'CredentialReplicaStoreTests|CredentialReconcilerTests|DriveSyncStoreTests'
  ```

  预期首次失败。
- [ ] 实现 replica 目录、原子写后校验和纯逻辑合并；每轮只更新当前设备文件。
- [ ] 重新运行相同测试，预期全部通过。

---

### 任务 4：实现一次性迁移与运行时接线

**文件：**

- 修改：`Sources/MacToolsCore/Settings/CredentialStore.swift`
- 修改：`Tests/MacToolsCoreTests/CredentialAccessCoordinatorTests.swift`
- 修改：`Sources/MacTools/App/Sync/KeychainCredentialStore.swift`
- 修改：`Sources/MacTools/App/Sync/ICloudDriveSyncCoordinator.swift`
- 修改：`Sources/MacTools/App/AppEnvironment.swift`
- 新增或修改：相关凭据同步协调测试

**接口：**

- `LegacyCredentialReading`：只读迁移协议。
- `CredentialAccessCoordinator`：串行执行本地加载、保存、删除和首次旧存储迁移。
- `ICloudDriveSyncCoordinator`：启动预取和每轮凭据对账，通过回调发布获胜状态。

- [ ] 改写协调器测试，覆盖以下顺序：
  - 本地 active/deleted 存在时不调用旧读取器；
  - 云端预取成功时不调用旧读取器；
  - 旧明文优先迁移并请求清除；
  - 只有无本地、无云端、无标记时读取 Keychain；
  - Keychain 不存在时写标记；
  - 拒绝或异常时不写标记；
  - 迁移成功后后续启动不再读取 Keychain；
  - 保存和删除均生成递增逻辑时钟。
- [ ] 运行：

  ```sh
  swift test --filter CredentialAccessCoordinatorTests
  ```

  预期首次失败。
- [ ] 将现有 Keychain 类收敛为只读迁移适配器，删除读取过程中的自动回写和删除行为。
- [ ] 调整启动顺序：同步已配置时先协调云端凭据；只有明确无云端记录时才执行旧存储迁移。
  未下载时请求下载并等待，不提前弹出 Keychain。
- [ ] 保存设置时先提交本地加密信封，成功后更新运行时并调度同步；本地失败保持旧值。
- [ ] iCloud 对账获胜后先写本地并验证，再通过 Main Actor 回调更新翻译模型。
- [ ] 重新运行协调器及任务 1–3 的全部聚焦测试。

---

### 任务 5：更新状态文案与当前产品文档

**文件：**

- 修改：`Sources/MacToolsCore/UI/TranslationSettingsEditor.swift`
- 修改：`README.md`
- 修改：`AGENTS.md`
- 修改：`findings.md`
- 修改：`docs/manual-verification.md`

- [ ] 将“Keychain 凭据不可访问”改为与新存储无关的通用凭据不可用文案。
- [ ] 更新 README 的同步范围、隐私说明和运行数据表，明确本地与 iCloud 均为密文。
- [ ] 更新 `AGENTS.md` 的百炼凭据专用边界，继续禁止真实密钥、明文副本和日志泄漏。
- [ ] 更新当前 iCloud findings；历史设计规格保留原结论，不重写为新方案。
- [ ] 在人工检查清单中增加：
  - 首次升级启动立即提示；
  - 构建 B 和重复启动不再提示；
  - iCloud 不可用时本地仍可翻译；
  - 新客户端从云端恢复；
  - 删除后旧设备值不复活。
- [ ] 运行相关设置测试并检查用户可见文案引用。

---

### 任务 6：完整验证、打包与提交

- [ ] 运行全部新增聚焦测试：

  ```sh
  swift test --filter 'CredentialEnvelopeCodecTests|EncryptedCredentialStoreTests|CredentialReplicaStoreTests|CredentialReconcilerTests|CredentialAccessCoordinatorTests|DriveSyncStoreTests'
  ```

- [ ] 运行完整测试：

  ```sh
  swift test
  ```

- [ ] 运行 `git diff --check` 和 `AGENTS.md` 中的完整隐私关键词扫描，逐项确认没有真实凭据。
- [ ] 运行：

  ```sh
  scripts/package_app.sh
  ```

  检查打包、签名和启动所需结构。
- [ ] 使用打包构建 A 启动；如果系统显示旧 Keychain 授权，由用户本人输入电脑密码，任何工具
  不读取或代填。
- [ ] 迁移成功后使用不同构建号生成构建 B，确认启动和再次启动都不再出现 Keychain 提示。
- [ ] 检查本地密文文件权限和格式，不输出或比较真实明文。
- [ ] 使用两个临时客户端验证跨设备恢复；真实第二台 Mac 的 iCloud 传播保留为人工验收边界。
- [ ] 因状态文案发生变化，运行 `scripts/rebuild_and_run_app.sh` 并检查设置页浅色/深色背景、
  聚焦、尺寸和 Liquid Glass 外轮廓。
- [ ] 只暂存本计划涉及文件，使用中文标题和正文创建 commit，并推送当前分支上游。
