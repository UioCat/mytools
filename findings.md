# Findings & Decisions

## User Constraints

- 用户没有付费 Apple Developer Program，Developer ID 不可作为可执行方案。
- 用户在多台自己的 Mac 上使用 MacTools。
- 需要继续通过 GitHub Release 和 Sparkle 提供更新。
- 公开产物不应暴露用户真实姓名和邮箱。
- 每台 Mac 可以接受首次安装时的一次系统确认，但后续更新不应反复产生多个 MacTools 权限项。
- 辅助功能、输入监控、自动粘贴和屏幕录制权限必须按每台 Mac 独立授权。

## Repository Findings

- 基线为 `main@c4b637a`，同时是 `v0.3.0` 和 `origin/main`，任务开始时工作树干净。
- `scripts/package_app.sh` 本机优先查找 Apple Development 等受信任身份，找不到时静默回退 ad-hoc。
- `.github/workflows/release.yml` 明确设置 `MACOS_FORCE_ADHOC_SIGNING=1`，每个标签都在 Runner 上生成新的 ad-hoc 应用。
- 当前运行包的 TCC 失败已经由 `tccd` 证明为 `anchor trusted` 与 ad-hoc `identifier-only` requirement 不匹配。
- 设置页权限状态只在 `.onAppear` 刷新，从系统设置返回时可能显示旧快照。
- 本机未安装 `gh` CLI；现有 GitHub Actions Runner 内仍可使用 `gh` 发布。主流程需要支持本机无需 `gh` 完成预签名产物交付或改用系统自带网络工具。
- 现有脚本测试只保证保留 ad-hoc 分支，没有覆盖“稳定发布必须拒绝 ad-hoc”、签名元数据清单或预签名产物验证。
- 现有 Release 测试只验证 Actions 自行生成 DMG/appcast 并发布，不具备接收本机预签名产物的可信边界。
- `create_dmg.sh` 只复制当前 `build/MacTools.app`，适合复用为本机唯一产物阶段。
- `macos_build_number.sh` 已提供可重复的语义构建号，预签名阶段和远程验证阶段应继续使用同一结果。
- GitHub 仓库是公开仓库；最新稳定 Release 为 `v0.3.0`，包含 DMG、SHA-256 和 `appcast.xml`，对应 Actions 成功运行。
- 本机存在一个有效 Apple Development 身份；证书名称和主体包含用户个人信息，公开签名产物会暴露这些字段。
- 本机 Keychain 没有以 `SPARKLE_PRIVATE_KEY` 为 service/label 的可直接读取项；现有远程 `SPARKLE_PRIVATE_KEY` Secret 已由成功发布证明可用。

## External Findings

- Apple Development 用于开发和测试；Developer ID Application 才是 Mac App Store 外正式发行证书。
- Apple 说明 ad-hoc designated requirement 与具体代码版本绑定，无法可靠跨重建识别隐私授权。
- Apple 支持将完整签名身份导出为加密 PKCS#12，但任何获得文件和密码的人都可以冒充该身份签名。
- GitHub API 直接 URL 无法由当前 Web 工具打开；这是工具边界，不是仓库或 Release 状态结论。

## Candidate Approaches

| Approach | Benefit | Cost / Risk |
| --- | --- | --- |
| Apple Development 固定签名 | TCC 身份稳定，工具链原生支持 | 公开真实姓名、邮箱与 Apple 证书标识；不符合隐私要求 |
| 固定匿名自签名 | 不公开个人信息，可用证书指纹和 Bundle ID 构造稳定 DR | 首次打开仍需 Gatekeeper 确认；需要保护独立私钥并实测 Sparkle/TCC |
| 继续 Actions ad-hoc | 无需管理证书且不公开身份 | DR 随代码变化，更新可能丢失 TCC 并生成重复权限项 |

## Privacy Decision

- 公开 Release 使用当前 Apple Development 身份会让下载者看到证书主体中的 QQ 邮箱、真实姓名、证书 UID/OU、序列号、有效期、指纹、公钥和 Apple 签发链。
- 不会暴露私钥、钥匙串密码、Apple Account 密码、登录令牌、地址或电话号码。
- 用户不接受上述个人身份公开，Apple Development 不进入公开 Release。
- 当前采用匿名自签名方向；公开证书仅包含 `MacTools Release Signing`、序列号、有效期、公钥与指纹。
- Designated Requirement 绑定 Bundle ID 与固定证书，不使用 `anchor trusted`，目标是避免要求每台安装机额外导入信任证书。

## Current Recommendation

- 生成一张带 Code Signing EKU、主题仅为 `MacTools Release Signing` 的长期匿名自签名证书。
- 主应用 DR 固定为 Bundle ID 与证书 SHA-1 指纹的组合，并额外记录 SHA-256 指纹用于审计；发布门禁拒绝 ad-hoc、Apple Development 和未知身份。
- 证书私钥只保存在主签名 Mac、第二台恢复 Mac 的 Keychain 和 GitHub Actions Secret；GitHub 托管 macOS Runner 使用 passwordless `sudo` 添加临时系统级 Code Signing 信任，任务结束即移除信任并销毁临时钥匙串。
- 所有 Mac 只运行 `/Applications/MacTools.app` 中的同一个 Release 产物；开发目录的 ad-hoc 包使用不同 Bundle ID 和显示名，不申请正式权限。
- 迁移版本提供一次性旧权限清理说明；仅对 `local.mactools.mvp` 执行 `tccutil reset All`，覆盖 Finder Automation 和屏幕录制等旧身份决定，但不触碰其他应用。
- 设置页在应用重新激活时刷新权限状态，避免用户已授权但界面仍显示“检查设置”。

## Prototype Findings

- `security create-keypair` 在临时钥匙串中只创建密钥对，没有生成可用的代码签名身份。
- `certtool c x=a` 生成的旧式自签名证书即使添加 `codeSign` 信任，也没有被 `codesign` 识别为有效身份。
- 两次失败原型均已删除临时钥匙串；第二次产生的临时用户信任也已移除。
- 实现必须先用带 `extendedKeyUsage=codeSigning` 的证书完成隔离签名原型，验证 `codesign --verify`、显式 DR 和移除签名机信任后的静态校验，再创建正式身份。

## Review Decisions

- 签名机和 GitHub Runner 必须临时信任自签名证书的 Code Signing 用途，否则身份可能无法被 `codesign` 选中；该信任只属于签名环境，安装机不导入证书。
- 签名身份变化影响所有按 DR 记录的 TCC 决定。迁移操作必须覆盖 Finder Automation 和屏幕录制，使用 `All + 精确 Bundle ID` 避免遗漏，同时限制影响范围。
- GitHub Actions Secret 不可回读，不能作为唯一恢复副本。发布前必须把同一身份导入第二台个人 Mac 的 Keychain，并用其签名测试产物验证可恢复性。
- 现有 Sparkle EdDSA 私钥在本机未找到，且没有 Developer ID 可供丢失后的安全轮换。实现阶段需用一次性 RSA 公钥在 Runner 内加密现有 Secret，下载密文后仅在本机临时解密并导入两台个人 Mac 的 Keychain；恢复公钥和 SHA-256 指纹固定在受审提交中，禁止由 dispatch 输入替换，任务只允许仓库所有者经受保护 Environment 审批后执行。
- GitHub 官方说明托管的 macOS Runner 支持 passwordless `sudo`。证书信任采用临时系统级 Code Signing trust，并先通过不发布产物的 `workflow_dispatch` 预检；用户级信任方案不采用。
- 恢复完成后删除密文 artifact、受保护 Environment 的临时配置、固定公钥和一次性 workflow；提交历史只保留无秘密的公开恢复公钥，不保留任何明文私钥。
