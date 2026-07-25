# MacTools 本地加密与 iCloud 凭据同步设计

## 文档状态

- 状态：设计已确认，待书面审阅后实施。
- 适用平台：macOS 26+。
- 目标凭据：百炼翻译提供方 `bailian` 的 `bailian.apiKey`。
- 使用场景：个人自用的本地打包应用会频繁重新构建，并需要通过同一 iCloud Drive 同步目录在多台 Mac 间直接恢复凭据。
- 已确认：不依赖稳定签名证书，不要求后续构建继续访问 Keychain。
- 已确认：应用启动时立即开始凭据加载和首次迁移，不等待用户首次打开翻译功能。

## 现状与原因

`AppEnvironment.start()` 当前会立即调用 `loadTranslationCredentialIfNeeded()`，再由
`CredentialAccessCoordinator` 读取 `KeychainCredentialStore`。现有服务名为
`com.mactools.credentials.v1`，由 ad-hoc 签名应用访问时会受具体代码身份约束。

固定 Bundle ID 和 identifier-only Designated Requirement 的方案已经使用两个不同
cdhash 的打包构建完成实机验证。构建 A 选择“始终允许”后，构建 B 仍出现 Keychain
授权提示，因此该方案已否决，结论记录在
`docs/superpowers/specs/2026-07-24-stable-adhoc-keychain-design.md`。

当前设置持久化已经通过 `PreferenceRepository` 清空 `translation.apiKey`，不会把凭据写入
SQLite；旧 `settings.json` 中可能残留的值由现有迁移流程读取后清除。新的存储方案继续保持
普通设置、SQLite、剪贴板同步快照和日志不含凭据。

## 目标与安全边界

| 范围 | 当前方案 |
| --- | --- |
| 本机启动 | 优先读取本地加密缓存，立即恢复翻译能力 |
| 多机同步 | iCloud Drive 中只保存经过认证加密的凭据副本 |
| 重新构建 | 不依赖签名身份、Bundle cdhash 或 Keychain ACL |
| 首次迁移 | 本地与云端均无记录时立即读取一次旧 Keychain，允许出现一次授权 |
| 后续启动 | 迁移完成后不再访问旧 Keychain，不再因应用重建请求电脑密码 |
| 离线使用 | iCloud 不可用时继续使用本地加密缓存 |
| 删除 | 同步加密删除标记，防止离线设备恢复旧值 |
| 防护目标 | 避免文件被直接打开、全文搜索、误传或意外采集时暴露明文 |

派生密钥所需材料随程序公开分发，不是真正秘密。任何同时取得兼容 App 和密文的人都可以
逆向或复现解密过程。本方案不防御恶意同用户进程、调试器、内存读取或针对 App 的逆向工程，
也不能让旧版 App 丧失解密其原本支持的旧格式的能力。

这是百炼 API Key 的专用产品边界，不把其他系统凭据改为相同存储方式，也不允许真实私钥、
随机密钥或用户凭据进入源代码。

## 方案选择

| 方案 | 优点 | 主要问题 | 结论 |
| --- | --- | --- | --- |
| 固定公开材料派生密钥 + AES-256-GCM | 重建和跨 Mac 稳定；支持完整性校验和格式版本 | 拿到 App 与密文即可复现解密 | 采用 |
| 直接硬编码 256 位字面密钥 | 实现直观 | 容易被误认为真正秘密；轮换和审查边界更差 | 不采用 |
| 随机密钥与密文分文件同步 | 表面上分离材料 | 同步目录同时包含两者，没有实际安全收益 | 不采用 |
| 设备绑定派生密钥 | 单机泄漏面较小 | 另一台 Mac 无法自动解密 | 不符合需求 |

本机只保存加密缓存，iCloud 保存加密副本。不会增加明文文件作为降级路径。

## 加密信封

### 密钥派生

`CredentialEnvelopeCodec` 使用 CryptoKit，从固定、公开、带版本的应用材料确定性派生
256 位 `SymmetricKey`。派生输入必须：

- 与签名、Bundle 路径、设备硬件和用户账号无关；
- 包含固定的用途标签和 `keyVersion = 1`；
- 在所有支持 v1 的 MacTools 构建中保持一致；
- 明确命名为公开派生材料，不以“隐藏私钥”或类似含义出现；
- 不提交随机生成的真实密钥字面量。

实现固定使用 `HKDF<SHA256>` 输出 32 字节结果，不保留算法分支。v1 使用以下公开 UTF-8
标签作为稳定协议常量：

| HKDF 输入 | v1 值 |
| --- | --- |
| input key material | `MacTools/PublicCredentialMaterial/v1` |
| salt | `MacTools/CredentialEnvelope/HKDF-SHA256` |
| info | `bailian.apiKey/AES-256-GCM/key-v1` |

不得从运行时 Bundle ID、签名、路径、硬件或账号补充输入。由于上述材料全部公开，HKDF 只
用于稳定派生和用途隔离，不宣称增加秘密强度。

### 数据格式

本地缓存和 iCloud 副本使用相同 JSON 信封：

```text
CredentialEnvelope
├── schemaVersion = 1
├── keyVersion = 1
├── credentialID = "bailian.apiKey"
├── clock
│   ├── counter
│   └── deviceID
└── sealedBox = Base64(AES-GCM combined representation)
```

AES-GCM 的 combined representation 包含随机 nonce、密文和认证标签。每次保存必须生成新
nonce，相同明文不能稳定产生相同密文。

`schemaVersion`、`keyVersion`、`credentialID` 和逻辑时钟使用开启 `.sortedKeys` 的
`JSONEncoder` 编码为规范头数据，并作为 Additional Authenticated Data。密封载荷包含：

| 字段 | 说明 |
| --- | --- |
| `state` | `active` 或 `deleted` |
| `value` | `active` 时为规范化后的凭据；`deleted` 时不存在 |
| `updatedAt` | 仅用于诊断和展示，不参与冲突胜负 |

任何头字段、密文或认证标签被修改都必须导致解密失败。解密后还要校验凭据类型、删除状态与
值的组合是否合法。

## 存储布局

### 本地缓存

在 `MacToolsStorePaths.storeDirectory` 下增加专用凭据目录：

```text
Store/
└── Credentials/
    ├── bailian-api-key.v1.json
    └── migration-v1.complete
```

- `Credentials` 目录权限设为 `0700`。
- 信封与迁移标记权限设为 `0600`。
- 使用临时文件、原子替换、权限重设和写后读回校验。
- `migration-v1.complete` 只记录迁移协议版本，不包含凭据、密文或设备信息。
- 删除凭据时保留包含 `deleted` 状态的信封和迁移标记。

### iCloud Drive

复用用户已选择的 `MacTools Sync` 根目录和现有安全作用域 bookmark：

```text
MacTools Sync/
└── credentials/
    └── replicas/
        └── <deviceID>.v1.json
```

每台设备只原子更新自己的小型加密副本，并扫描其他未移除设备的副本。这与现有同步的设备
ID、removed-device 标记和 replica 模式一致，可避免多台 Mac 同时覆盖同一个 iCloud 文件。
旧版本会忽略新增目录，不需修改现有同步协议版本。

iCloud 文件权限不作为安全边界；云端只允许出现信封头和密文。所有读取和写入继续位于
`ICloudDriveSyncCoordinator` 的后台队列，并在根目录的 `NSFileCoordinator` 协调范围内完成。

## 组件边界

| 组件 | 职责 | 依赖 |
| --- | --- | --- |
| `CredentialEnvelopeCodec` | 派生 v1 密钥，密封、打开并校验信封 | CryptoKit、Foundation |
| `EncryptedCredentialStore` | 本地原子读写、权限、迁移标记和写后校验 | 文件系统、codec |
| `CredentialReplicaStore` | 读取和写入 iCloud 设备副本，识别未下载与损坏文件 | 文件系统、codec |
| `CredentialReconciler` | 比较逻辑时钟，选择 active 或 deleted 胜者 | 纯模型逻辑 |
| `CredentialAccessCoordinator` | 串行执行启动、保存、删除和一次性旧存储迁移 | 上述组件、只读 Keychain 迁移适配器 |
| `ICloudDriveSyncCoordinator` | 提供已协调的同步根目录并触发凭据对账 | bookmark、`NSFileCoordinator` |
| `AppEnvironment` | 启动时立即触发加载，把结果发布给运行时模型 | coordinator、现有设置模型 |

可复用模型、codec、合并决策和文件存储位于 `Sources/MacToolsCore`；Security.framework 查询和
AppKit 生命周期接线保留在 `Sources/MacTools/App`。

## 启动与迁移

### 普通启动

1. `AppEnvironment.start()` 立即启动凭据加载任务，不等待翻译面板或首次请求。
2. `CredentialAccessCoordinator` 在非 Main Actor 执行本地文件和旧存储 I/O。
3. 本地有效 `active` 信封立即发布凭据；本地 `deleted` 信封立即发布未配置状态。
4. 同步已启用且根目录可用时，后台读取 iCloud 副本并执行对账。
5. 云端胜出时更新本地信封并发布新状态；本地胜出时更新当前设备的云端副本。
6. iCloud 不可用、文件尚未下载或同步关闭时，本地结果不受影响。

### 首次升级

只有本地信封不存在、云端没有可用记录且 `migration-v1.complete` 不存在时，才进入旧存储
迁移：

1. 旧 `settings.json` 中存在非空凭据时，优先将其写成新信封并清除旧明文，不访问 Keychain。
2. 没有旧明文时，通过只读适配器立即查询 `com.mactools.credentials.v1` 和现有历史
   Keychain 服务；查询过程不得自动保存、更新或删除任何 Keychain 项目。
3. 系统可以在此处显示一次授权提示；用户自行在系统窗口输入电脑密码，应用不得读取或记录。
4. 取得凭据后，先写本地 `active` 信封并读回验证，再写迁移标记并发布运行时状态。
5. iCloud 写入异步执行；云端失败不影响本机迁移完成，后续同步重试。
6. Keychain 明确返回不存在时写迁移标记并保持未配置，避免每次启动重复查询。
7. 用户拒绝授权或查询异常时不写迁移标记、不删除旧条目，其他功能继续运行。

迁移成功后不自动删除旧 Keychain 项目，避免产生额外授权或不可恢复的数据损失。后续启动、
保存和删除只使用新存储，不再访问 Keychain。

### 新 Mac

新 Mac 在同步设置中选择同一个 `MacTools Sync` 目录并启用同步后：

1. 请求下载尚未落地的凭据副本；
2. 解密所有可读取副本并选择获胜版本；
3. 将获胜信封写入本地缓存并校验；
4. `active` 状态直接恢复翻译，`deleted` 状态保持未配置；
5. 不需要签名证书、电脑密码或手工导入密钥。

如果同步目录尚未配置或不可用，新 Mac 保持未配置；恢复目录后自动重试。

## 保存、删除与冲突

使用现有 `ClipboardFieldClock` 的比较语义：计数器较大者获胜，计数器相同则
`deviceID` 字典序较大者获胜。每次本地保存或删除时，新计数器取当前已知最大值加一。

### 保存

1. 规范化用户输入并创建新的 `active` 信封。
2. 原子写入本地并完成读回解密校验。
3. 本地成功后才更新内存中的凭据和设置状态。
4. 设置持久化继续清空 `translation.apiKey`，只在运行时模型中保留解密值。
5. 同步启用时安排 iCloud 写入；失败显示现有同步错误并周期重试。

本地写入或校验失败时，保存操作失败，当前已生效的旧凭据保持不变。

### 删除

空值保存转换为带更高逻辑时钟的 `deleted` 信封。删除标记同时保存在本地和当前设备的
iCloud replica 中，不直接移除文件。这样离线设备重新上线时，其较旧 `active` 副本不能复活
凭据。

### 对账

- 只比较成功通过认证和结构校验的信封。
- 本地与所有云端副本中逻辑时钟最大的信封为胜者。
- 相同信封重复处理必须幂等。
- 云端胜出时先写本地并验证，再发布运行时状态。
- 当前设备的 replica 与获胜信封不一致时，写入当前设备 replica；不重写其他设备文件。
- 已有 removed-device 标记的设备副本不参与比较；移除设备前，当前设备必须先保存已验证的
  获胜信封，避免唯一有效副本随设备移除而丢失。
- iCloud 冲突版本由现有文件冲突检查处理；无法证明内容一致时不自动选边。

并发修改属于逻辑并发，确定性 device ID 规则保证所有设备最终选择同一结果，不承诺保留被
覆盖的旧凭据版本。

## 异常处理

| 场景 | 处理 |
| --- | --- |
| 本地信封损坏、云端有有效版本 | 使用云端胜者修复本地 |
| 云端部分副本损坏 | 忽略损坏副本，保留有效本地或其他副本，状态显示同步失败 |
| 本地与云端均无法解密 | 不读取已完成迁移的旧 Keychain，要求重新输入 |
| `schemaVersion` 不支持 | 不覆盖当前有效状态，报告协议不兼容 |
| `keyVersion` 不支持 | 不尝试错误密钥，报告凭据版本不兼容 |
| iCloud 文件未下载 | 请求下载并进入等待状态；本地凭据继续可用 |
| iCloud 根目录或 bookmark 失效 | 本地继续可用，要求重新选择同步目录 |
| 本地保存失败 | 不更新运行时值，不调度云端覆盖 |
| 云端保存失败 | 本地保存成功，标记待同步并周期重试 |
| 首次 Keychain 授权被拒绝 | 本次凭据不可用；不标记迁移完成、不删除旧条目 |
| 应用在原子替换前退出 | 保留上一份完整信封，下次启动重试 |

日志只记录阶段、错误类型和版本信息，不记录凭据、解密结果、密文、请求头或 Keychain 返回
数据。

## UI 与用户行为

不新增设置入口或密钥管理界面：

- 继续通过现有翻译设置保存或清空百炼 API Key。
- 凭据不可用时复用 `TranslationCredentialViewModel.isUnavailable`。
- iCloud 等待下载、目录不可用和同步失败复用现有 `SyncStatus`。
- 首次升级的 Keychain 系统窗口在 App 启动阶段直接出现，不采用懒加载。
- 非翻译功能不因凭据迁移、解密或同步失败而停止。

由于没有新增或调整界面布局，本方案不需要新的 UI 视觉设计；若实施中修改用户可见文案，
需要同步更新 `docs/manual-verification.md` 并完成打包应用视觉检查。

## 实施范围

| 位置 | 调整 |
| --- | --- |
| `Sources/MacToolsCore/Settings/` | 增加加密信封、文件存储、对账模型并调整凭据协调器 |
| `Sources/MacToolsCore/Storage/MacToolsStorePaths.swift` | 增加本地凭据目录、信封和迁移标记路径 |
| `Sources/MacToolsCore/Sync/` | 增加 iCloud 凭据 replica 存储和逻辑时钟合并 |
| `Sources/MacTools/App/Sync/` | 增加只读 Keychain 迁移适配器，把凭据对账接入现有文件协调队列 |
| `Sources/MacTools/App/AppEnvironment.swift` | 注入新存储并保持启动阶段立即加载 |
| `Tests/MacToolsCoreTests/` | 覆盖 codec、文件存储、迁移、对账和同步行为 |
| `docs/manual-verification.md` | 记录首次迁移、重复构建与跨设备恢复检查 |
| `AGENTS.md` | 将百炼凭据约定更新为本方案的专用加密同步边界 |

打包脚本和 ad-hoc 签名策略不为本方案改变。测试创建的历史 Keychain 条目也不在实施过程中
自动删除；任何清理都需要用户明确授权。

## 验证

### 自动化测试

| 场景 | 预期 |
| --- | --- |
| AES-GCM 密封后打开 | 恢复原值，且相同输入两次产生不同密文 |
| 修改信封头、密文或认证标签 | 解密失败，不返回部分数据 |
| 错误 schema、key version 或 credential ID | 明确拒绝，不使用错误格式 |
| 本地保存 | 原子写入、权限为 `0600`、读回校验成功 |
| 本地写入或校验失败 | 旧信封和当前运行时值保持不变 |
| 两个设备 replica 交错写入 | 按逻辑时钟确定性收敛 |
| 保存与删除并发 | 获胜 tombstone 可阻止较旧 active 值复活 |
| 已移除设备仍保留旧 replica | 该副本不参与合并，当前设备保留已验证的获胜信封 |
| iCloud 写入失败 | 本地可用并保留待同步状态 |
| 云端胜出 | 先修复本地，验证成功后再发布 |
| 旧明文存在 | 直接加密并清除旧明文，不查询 Keychain |
| 旧 Keychain 存在 | 只在首次启动读取，迁移成功后不再调用 |
| Keychain 返回不存在 | 写迁移标记，后续启动不再查询 |
| Keychain 授权失败 | 不提前标记完成，可在后续启动重试 |
| 已删除或迁移完成 | 不因本地空值回退读取旧 Keychain |

迭代阶段先运行新增测试类和现有 `CredentialAccessCoordinatorTests`、`DriveSyncStoreTests`，
再运行完整 `swift test`。测试一律使用临时目录和占位值，不访问真实 iCloud、Keychain 或用户
凭据。

### 打包应用验证

1. 使用构建 A 打包并启动，确认启动阶段立即迁移旧 Keychain 凭据，系统最多提示一次。
2. 用户在系统窗口完成授权后，确认翻译可用，本地信封存在且权限正确。
3. 使用不同构建号 B 重新打包并替换应用，确认不再出现 Keychain 授权，翻译仍可用。
4. 再次退出和启动构建 B，确认继续无提示。
5. 在不输出真实值的前提下，确认设置、SQLite、日志和 iCloud 同步目录不存在明文凭据。
6. 使用两个隔离临时客户端和同一同步目录模拟两台 Mac，验证第二个客户端不访问 Keychain
   即可从 iCloud 信封恢复占位凭据。
7. 物理第二台 Mac 选择同一 iCloud 目录后的自动恢复作为人工验收项；单机自动化结果不能
   冒充真实 iCloud 多机传播证据。

打包和运行时验证使用 `scripts/rebuild_and_run_app.sh` 或 `scripts/package_app.sh` 生成的
`build/MacTools.app`，不以 `swift run MacTools` 作为签名或 Keychain 行为证据。

## 参考

- [AES.GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm)
- [AES.GCM.seal](https://developer.apple.com/documentation/cryptokit/aes/gcm/seal%28_%3Ausing%3Anonce%3A%29)
- [SymmetricKey](https://developer.apple.com/documentation/cryptokit/symmetrickey)
- [NSFileCoordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator)
- [iCloud](https://developer.apple.com/documentation/foundation/icloud)
- [Storing Keys in the Keychain](https://developer.apple.com/documentation/security/storing-keys-in-the-keychain)
