# MacTools 匿名稳定签名与多机权限设计

## 文档状态

- 状态：已确认，实施中。
- 适用平台：macOS 26+，用户自己的多台 Mac。
- 约束：没有付费 Apple Developer Program，不使用 Developer ID，不公开个人 Apple Development 证书。
- 目标版本：由发布判断在实现和完整验证后确定，预计为补丁版本。

## 目标

为公开 GitHub Release 建立一套不包含用户姓名、邮箱或 Apple 账号标识的固定代码签名身份，使 macOS 能够跨版本识别同一个 MacTools，并把多机体验收敛为：

1. 每台 Mac 首次下载后只确认一次“仍要打开”；
2. 每台 Mac 只对 `/Applications/MacTools.app` 授予一次所需系统权限；
3. 后续 Sparkle 更新沿用同一代码身份，不再因重新构建产生多个 MacTools 权限项；
4. 当前 ad-hoc 版本迁移时只做一次旧权限整理和重新授权；
5. GitHub Release 继续发布 DMG、SHA-256 和经 EdDSA 签名的 `appcast.xml`。

## 现状与根因

当前 GitHub Actions 明确强制 ad-hoc 签名。Apple 的 TN3127 说明 ad-hoc Designated Requirement（DR）与具体代码版本绑定，不能可靠地让 TCC 将新构建识别为旧构建的更新。

现有本机包与公开 Release 还可能来自不同路径和不同签名分支：

- `build/MacTools.app` 可能使用本机 Apple Development 证书；
- `/Applications/MacTools.app` 来自 GitHub 的 ad-hoc Release；
- `swift run` 或旧 DerivedData 可执行文件曾直接请求系统权限。

这些代码身份和运行路径混用后，辅助功能、输入监控和自动粘贴列表会保留多个 MacTools 条目。设置页只在首次出现时读取权限，也会造成系统已授权而应用仍显示“检查设置”的假象。

## 方案比较

| 方案 | 隐私 | 跨版本身份 | 首次打开 | 结论 |
| --- | --- | --- | --- | --- |
| Apple Development | 暴露姓名、邮箱和 Apple 标识 | 稳定 | 仍不是 Developer ID 公证发行 | 不采用 |
| 固定匿名自签名 | 只公开项目证书名和密码学元数据 | 可由固定证书 DR 保持 | 每台 Mac 首次需“仍要打开” | 采用 |
| ad-hoc | 不公开身份 | 随构建变化 | 每版都可能重新确认 | 不采用稳定渠道 |

Developer ID 签名与 Apple 公证是消除未识别开发者提示的正式路径，但需要付费开发者计划。当前方案不伪装成 Developer ID，也不降低 Gatekeeper；它只在用户明确首次批准后提供稳定的本地代码身份。

## 固定匿名代码身份

### 证书内容

创建独立的自签名代码签名证书，证书主体只包含：

```text
Common Name = MacTools Release Signing
```

证书要求：

- P-256 椭圆曲线公钥；
- SHA-256 签名；
- Basic Constraints 为自签名根 `CA:TRUE, pathlen:0`；
- Key Usage 仅包含 Digital Signature 与 Certificate Sign，后者只用于让该固定自签名证书在签名环境中作为信任根；
- Extended Key Usage 包含 Code Signing；
- 长期固定有效期，目标为 20 年；
- 不填写姓名、邮箱、组织、组织单元、地区或 Apple Team 标识。

公开应用必然包含证书、公钥、序列号、有效期和指纹。这些字段只描述 MacTools 的匿名发布身份，不映射到用户个人资料。私钥不得进入仓库、日志、Release 资产或普通持久文件。

固定公开元数据：

| 字段 | 值 |
| --- | --- |
| 有效期 | 2026-08-09 至 2046-08-09（UTC） |
| SHA-1 | `25A3263958804C6D9429EB51B97BA2B16CA1FB67` |
| SHA-256 | `D098182A8CFA254D9834F5E0E7911C39418080D38B1AC921E8F90E90DDE3E157` |
| P-256 公钥 SHA-256 | `D5B6541A61CE08813F5FA2C36862B40AC0CD992F8D6352FDFB1EDF23231FACFE` |

### Designated Requirement

主应用显式使用固定 DR：

```text
identifier "local.mactools.mvp"
and certificate leaf = H"25A3263958804C6D9429EB51B97BA2B16CA1FB67"
```

证书指纹是公开的身份锚点，不是秘密。该 requirement 不使用 `anchor trusted`，因此目标机器无需额外安装或信任自签名根证书即可判断更新是否由同一固定证书签署。实现阶段必须以未安装该证书的隔离环境验证这一行为，未通过时停止发布。

所有 Sparkle framework、XPC service、Updater 和主应用都由同一匿名身份按由内到外的顺序签名。发布门禁同时检查：

匿名自签名和开发 ad-hoc 签名都没有 Apple Team ID。主应用为加载随包分发且已单独验签的 Sparkle Framework，仅声明 `com.apple.security.cs.disable-library-validation`；Hardened Runtime 及其他保护保持启用，Sparkle 嵌套组件不继承该例外。

- 主应用不是 ad-hoc；
- `Authority` 仅为 `MacTools Release Signing`；
- 没有 TeamIdentifier 和个人 Apple Development Authority；
- 主应用 DR 与仓库记录的证书指纹、Bundle ID 完全一致；
- 嵌套组件与主应用签名完整且满足各自 DR。

## 密钥生命周期

### 用途隔离派生

现有 `SPARKLE_PRIVATE_KEY` 作为唯一发布根密钥。代码签名不直接复用 Ed25519 私钥字节，而是使用 HKDF-SHA256 和固定的版本化用途标签派生独立 P-256 标量。派生脚本必须：

- 拒绝空根密钥、零标量以及不在 P-256 群阶内的值；
- 只将私钥写入权限为 `0700` 的临时目录，文件权限为 `0600`；
- 导入 Keychain 前校验派生公钥与仓库固定证书完全一致；
- 绝不输出根密钥、派生标量、私钥 PEM 或临时 Keychain 密码。

此方案不新增 GitHub Secret，标签发布仍只使用现有 `SPARKLE_PRIVATE_KEY`。代价是该根密钥泄露时 Sparkle 更新签名和代码签名会同时受影响；两个子用途在密码学上相互隔离，但共享同一根密钥的运维风险边界。

### 本机

正式身份只创建一次。创建前先在隔离临时钥匙串中验证带 Code Signing EKU 的原型证书能够：

1. 签名测试二进制和完整 MacTools.app；
2. 通过 `codesign --verify --deep --strict`；
3. 在签名机移除临时证书信任后仍满足显式 DR；
4. 不包含任何个人字段。

原型通过后，Sparkle 根私钥只导入主签名 Mac 和第二台恢复 Mac 的登录 Keychain。代码签名子私钥每次按需派生，导入临时 Keychain 后即销毁普通文件，不作为独立备份或 GitHub Secret。正式发布前必须在第二台 Mac 重复派生公钥、证书和 DR 检查，未完成该恢复演练时不得创建版本标签。

现有 Sparkle EdDSA 私钥只确认存在于不可回读的 GitHub Secret，本机 Keychain 尚未找到恢复副本。实现阶段增加一次性、由 Git Push 触发的密钥恢复工作流：

1. 本机在权限为 `0700` 的临时目录生成一次性 RSA 4096 恢复密钥；私钥不离开本机，公钥和其 SHA-256 指纹写入一次性 workflow 所在的受审提交；
2. workflow 不接受恢复公钥、指纹或收件人输入，运行时先对仓库内固定公钥重新计算并比对固定指纹；
3. workflow 只监听 `codex/sparkle-key-recovery` 分支，恢复 job 只允许 `github.actor == github.repository_owner`；
4. 工作流将 `SPARKLE_PRIVATE_KEY` 通过标准输入交给 RSA-OAEP-SHA256 加密，日志只记录公钥指纹，不得打印明文；
5. Runner 使用当次 `GITHUB_TOKEN` 将密文提交到以源提交 SHA 命名的临时输出分支，该分支只增加 RSA 密文；
6. 本机使用现有 Git SSH 获取精确输出分支，在临时目录解密后立即用 Sparkle 工具导入登录 Keychain；
7. 确认导入私钥派生的公钥与应用现有 `SUPublicEDKey` 完全一致，再完成 DMG 和 appcast 的签名、验证；
8. 通过加密临时传输把同一 EdDSA 私钥导入第二台恢复 Mac 的 Keychain，并重复公钥匹配和签名验证；
9. 删除两台 Mac 的临时明文、一次性 RSA 私钥、远程密文分支、固定恢复公钥和一次性 workflow。

该流程只恢复仓库原有 Secret，不生成或轮换 Sparkle 密钥。对 workflow、公钥或 actor 限制的任何未审修改都必须阻断执行；任一步无法验证时停止发布。没有 Developer ID 时不得假设能够安全轮换丢失的 EdDSA 密钥。

恢复 workflow 的第三方 Action 必须固定到已核验的完整提交 SHA，checkout 不持久化凭据；只有最后发布密文分支的步骤才获得 `GITHUB_TOKEN` 环境变量。

### GitHub Actions

GitHub Actions Secrets 仅保留：

| Secret | 内容 |
| --- | --- |
| `SPARKLE_PRIVATE_KEY` | 现有 EdDSA 私钥 |

Runner 从 `SPARKLE_PRIVATE_KEY` 派生代码签名子私钥，校验公钥后只导入任务级临时 Keychain。导入脚本先检查签名环境是否已有该固定证书的 Code Signing 信任：维护者本机可以只确认一次登录 Keychain 的用户级信任；全新的 GitHub Runner 没有该信任时，再利用托管 macOS 虚拟机的 passwordless `sudo` 添加以下系统级临时信任：

```text
sudo security add-trusted-cert -d -r trustRoot -p codeSign \
  -k /Library/Keychains/System.keychain <public-certificate>
```

工作流必须先用 `security find-identity -v -p codesigning` 证明身份有效，随即删除普通文件中的派生私钥和临时 PKCS#12，再限制钥匙串搜索范围并开始构建。稳定 App 签名完成后立即删除临时 Keychain，并且只在本次任务实际添加系统信任时执行 `sudo security remove-trusted-cert -d`；不得删除维护者已有的用户级信任。工作流末尾仍以 `always()` 重复执行幂等清理，覆盖构建中途失败。首次接入先由 owner-only 的 `codex/anonymous-signing-preflight` push 分支运行不创建标签、不上传 Release 的签名预检；只有实际 Runner 证明整个派生、信任、签名、验证和清理过程无交互通过后，才允许合入标签发布路径。工作流不得打印 Secret、证书导出密码或私钥内容。

签名环境的临时信任只用于让 `codesign` 选择并使用自签名身份，不得混同为安装要求。普通安装 Mac 不导入或信任证书；其首次运行仍由 Gatekeeper 的“仍要打开”流程确认，后续代码身份由固定 DR 供 macOS/TCC 匹配，Sparkle 更新完整性另由 EdDSA 签名校验。

私钥泄露会允许攻击者制作满足同一 DR 的恶意 MacTools，因此代码签名私钥与 Sparkle EdDSA 私钥均按发布密钥处理。任何疑似泄露都阻断发布；匿名证书轮换需要独立迁移设计，不能直接替换。

## 构建与发布

### 签名模式

`scripts/package_app.sh` 将签名模式显式分开：

| 模式 | Bundle ID / 名称 | 用途 |
| --- | --- | --- |
| `stable` | `local.mactools.mvp` / `MacTools` | 本机正式包和 GitHub Release；缺少固定身份时立即失败 |
| `development` | 独立开发标识 / `MacTools Dev` | 公开仓库贡献者本地编译；允许显式 ad-hoc，不复用正式 TCC 权限 |

稳定模式禁止自动选择 Apple Development，也禁止静默回退 ad-hoc。证书名和固定指纹由公开配置给出，脚本必须同时匹配二者，避免同名伪造或误选身份。

### 唯一正式路径

正式使用只运行：

```text
/Applications/MacTools.app
```

`scripts/rebuild_and_run_app.sh` 在稳定模式下先完成签名验证，再替换该固定路径并启动；不再从 `build/MacTools.app` 申请正式权限。开发模式使用独立的 `build/MacTools Dev.app`、名称和 Bundle ID，并移除正式 Sparkle feed 与公钥；脚本发现另一身份仍在运行时会明确失败，避免两个身份并发访问同一份本地数据或注册相同快捷键。

### GitHub Release

标签触发的发布工作流改为：

1. 从现有 `SPARKLE_PRIVATE_KEY` 派生并验证匿名身份，导入临时 Keychain；
2. 复用已有 Code Signing 信任，或使用 passwordless `sudo` 添加仅限本次任务的临时系统信任，并验证身份有效；
3. 以 `stable` 模式构建并签名应用，随后立即销毁临时签名 Keychain 和任务所加系统信任；
4. 在不保留临时签名身份的条件下验证应用，并检查签名主体不含邮箱、姓名、Apple Development 或未知字段；
5. 创建 DMG 和 SHA-256；
6. 使用现有 Sparkle EdDSA 私钥生成并验证签名 appcast；
7. 发布非草稿 GitHub Release；
8. 回读 DMG、校验和、appcast 与 latest 地址并再次验证；
9. 无论成功或失败均执行幂等兜底清理，并且只移除本次任务添加的临时系统信任。

Release 说明不再声称“ad-hoc 更新后可能重复授权”，改为说明首次从旧签名迁移需要一次权限整理，后续同一签名更新应保留授权。

## 多机安装与权限迁移

### 新 Mac

每台新 Mac 的固定流程为：

1. 从 GitHub Release 下载并校验 DMG；
2. 拖入 `/Applications`；
3. 首次被 Gatekeeper 阻止后，在“隐私与安全性”点击“仍要打开”；
4. 在 MacTools 设置中按需授予辅助功能、输入监控、自动粘贴和屏幕录制权限；
5. 后续只通过 Sparkle 或同一 Release 包升级。

TCC 权限属于每台 Mac 的本地安全决定，不通过 iCloud 或应用数据同步。证书私钥不会分发给其他 Mac；运行 Release 只需要应用内嵌的公开证书。

### 旧版本迁移

当前 ad-hoc TCC 身份无法转换为新证书身份，因此迁移版本允许且仅允许一次重新授权：

1. 退出所有旧 MacTools、`swift run` 和 DerivedData 实例；
2. 删除非 `/Applications/MacTools.app` 的旧运行副本；
3. 在系统设置的辅助功能和输入监控列表中，用减号删除旧 MacTools、`MacTools.app` 或原始可执行文件条目；
4. 安装新 Release 到固定路径并首次打开；
5. 重新授予辅助功能、输入监控、自动粘贴和屏幕录制权限，并在首次使用 Finder 目录功能时重新允许 Finder Automation。

应用内提供带确认说明的“整理旧权限记录”入口，只调用：

```text
tccutil reset All local.mactools.mvp
```

该操作会一次性清除 MacTools 旧身份的辅助功能、输入监控、自动粘贴、屏幕录制和 Finder Automation 决定，但不会重置其他应用。确认框必须明确列出影响，并要求用户随后逐项重新授权。无法按 Bundle ID 删除的历史裸可执行文件条目，继续明确引导用户使用系统设置中的减号完成一次性清理。

## 权限状态刷新

权限页保留现有四行状态，但运行时增加应用重新激活刷新：

- 打开权限设置前先触发对应系统注册请求；
- 用户从系统设置返回、MacTools 再次成为活动应用时重新读取真实权限；
- 权限整理结束后立即刷新，并提示需要退出重开才能让事件监听器重新建立；
- 不用定时轮询 TCC，也不读取受保护的 TCC 数据库。

Finder Automation 没有加入现有四行常驻状态，因为系统没有与其他四项等价的无提示预检接口；迁移流程仍必须覆盖它，并在第一次需要读取 Finder 当前目录时验证首次提示、允许、拒绝、撤销和重新授权路径。

## Sparkle 更新连续性

现有 Sparkle EdDSA 公钥和私钥不变。代码签名解决 macOS/TCC 身份，EdDSA 继续验证下载包和 appcast 来源，两者互不替代。

正式发布前必须完成一次真实更新：

1. 用相同匿名证书构建较低版本 A；
2. 在打包应用中授予测试所需权限；
3. 让版本 A 从稳定 appcast 发现并安装目标版本 B；
4. 验证版本、路径和签名已变为 B；
5. 验证辅助功能、输入监控和自动粘贴仍被识别为同一应用；
6. 验证系统设置没有新增第二个正式 MacTools 条目。

该验证未通过时不得创建版本标签。若 Sparkle 对非 Developer ID 自签名更新存在额外限制，保留 EdDSA 校验但停止自动替换，重新评估分发方式，不绕过更新验证。

## 异常与边界

| 场景 | 处理 |
| --- | --- |
| 稳定身份缺失或指纹不符 | 打包立即失败，不回退 ad-hoc 或 Apple Development |
| `SPARKLE_PRIVATE_KEY` 缺失或派生公钥不匹配 | 工作流在构建前失败，不创建 Release |
| 证书包含个人字段 | 隐私扫描失败，禁止打包和发布 |
| 证书过期或签名无法验证 | 阻断发布，先设计兼容迁移；不自动换证 |
| 用户没有清理历史裸可执行文件 | 新版本仍只产生一个稳定身份；旧条目由用户一次性用减号删除 |
| 用户在另一台 Mac 安装 | 重复该机首次 Gatekeeper 与 TCC 授权；不复制权限数据库 |
| Sparkle/EdDSA 校验失败 | 拒绝更新并保留当前可运行版本 |
| 私钥疑似泄露 | 停止发布，撤销相关 Secrets，另行设计身份迁移 |
| 主签名 Mac 丢失 | 使用第二台恢复 Mac Keychain 中已演练的同一身份继续发布，不轮换证书 |
| Sparkle Secret 或账号不可用 | 使用两台恢复 Mac Keychain 中已演练的同一 EdDSA 私钥继续签名；无恢复副本时阻断发布 |

## 测试与验证

### 自动化

- 打包脚本测试覆盖稳定模式拒绝缺失身份、拒绝 ad-hoc、拒绝 Apple Development、匹配固定指纹和正确 DR。
- 工作流源码测试覆盖 HKDF 用途隔离、临时 Keychain、根 Secret 缺失门禁、公钥匹配、隐私字段扫描、稳定签名验证和清理步骤。
- owner-only 的非发布 push 预检覆盖 Runner 系统级信任的添加、有效身份发现、签名验证、对称清理以及无 Release 副作用。
- 权限服务测试覆盖 `All + local.mactools.mvp` 的精确命令，不允许缺少 Bundle ID 的全局重置。
- 权限 UI/运行时测试覆盖应用重新激活时刷新和整理后的状态变化。
- 运行聚焦测试、完整 `swift test`、严格并发构建和 `git diff --check`。

### 打包与实机

1. 运行 `scripts/package_app.sh` 构建稳定包，检查主应用和所有嵌套签名；
2. 从证书和签名中提取公开字段，确认不存在姓名、邮箱、Apple UID/OU 或 TeamIdentifier；
3. 启动 `/Applications/MacTools.app`，验证权限页从系统设置返回后即时刷新；
4. 运行一次仅针对 MacTools Bundle ID 的权限整理，确认其他应用不受影响，并重新授予屏幕录制与 Finder Automation；
5. 在辅助功能、输入监控和自动粘贴已授权条件下验证超级右键短按、长按与自动粘贴；同时覆盖 Finder Automation 的允许、拒绝、撤销和重新授权；
6. 完成较低版本到目标版本的真实 Sparkle 更新，确认权限和系统设置条目连续；
7. 运行敏感信息扫描，人工复核证书公开字段和工作流日志。

### 发布后

- 等待标签工作流成功并确认 Release 非草稿；
- 下载公开 DMG、SHA-256 和 appcast，重新计算校验和并验证 EdDSA；
- 挂载 DMG 后重复代码签名、DR 和隐私字段检查；
- 确认 `releases/latest/download/appcast.xml` 与本次资产一致；
- 由独立发布判断角色复核公开资产，而不是只查看工作流绿色状态。

## 参考

- [TN3127: Inside Code Signing: Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)
- [Applying Code Requirements](https://developer.apple.com/documentation/security/applying-code-requirements)
- [Code Signing Requirement Language](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html)
- [Safely open apps on your Mac](https://support.apple.com/102445)
- [Sparkle documentation](https://sparkle-project.org/documentation/)
- [GitHub-hosted runners reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
