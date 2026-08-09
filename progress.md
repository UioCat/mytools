# Progress Log

## Session: 2026-08-09

### Phase 1: Baseline & Design

- **Status:** in_progress
- Actions taken:
  - 确认用户无付费开发者计划、需要多台自有 Mac 使用并要求发布到 GitHub Release。
  - 记录 Git 基线：`main@c4b637a`、`v0.3.0`、`origin/main`、工作树干净。
  - 核对现有发布工作流强制 ad-hoc，确定其与 TCC 身份失配根因一致。
  - 比较固定 Mac 本机签名、CI 导入开发证书和继续 ad-hoc 三种方向。
  - 通过 GitHub REST 确认仓库公开、`v0.3.0` Release 与发布工作流成功。
  - 确认 Apple Development 证书主体含邮箱；公开 Release 存在可识别的隐私暴露。
  - 只读解析证书，确认还包含真实姓名、UID/OU、序列号、有效期、指纹、公钥和 Apple 签发链；不包含私钥或账号密码。
  - 确认本机没有按约定名称保存的 Sparkle 私钥，远程 Secret 仍是已验证签名源。
  - 用户确认不公开姓名与邮箱，方案切换为固定匿名自签名身份。
  - 查阅 Apple Code Signing requirement 与 Sparkle EdDSA 文档，确认 TCC 身份依赖稳定 DR，首次 Gatekeeper 确认无法在免费方案下消除。
  - 在临时钥匙串验证 `security create-keypair` 和 `certtool`；二者均不能直接生成 `codesign` 可用身份，相关临时钥匙串和信任已清理。
  - 独立设计 Review 发现 Runner 信任、Finder Automation 迁移和私钥恢复三项缺口；设计补充签名环境临时信任、Bundle ID 级全部 TCC 重置和第二台 Mac Keychain 恢复演练。
  - 同一 Agent 复审发现用户级信任不能保证无人值守、迁移步骤仍写“三项权限”、Sparkle 私钥只有不可回读 Secret；设计改用临时系统级 trust，并增加加密恢复和双机 Keychain 演练。
  - 第三次复审发现可变恢复公钥会把工作流变成 Secret 导出接口；设计改为公钥和指纹固定、仓库所有者限定、受保护 Environment 审批及完成后清理。
  - 同一独立 Review Agent 第四轮确认无未解决 P0-P2；独立发布判断确认本次仅文档提交为 `none`，不创建标签或 Release。

## Verification Log

| Check | Result |
| --- | --- |
| Git baseline | `main@c4b637a`, clean |
| Current stable tag | `v0.3.0` |
| Current release signing | GitHub Actions forces ad-hoc |
| Local signing identity | Valid Apple Development identity available |
| GitHub repository | Public |
| Latest stable release | `v0.3.0`, published, expected three assets |
| Local Sparkle signing key | Not found under `SPARKLE_PRIVATE_KEY` service/label |
| Anonymous identity privacy | Subject limited to `MacTools Release Signing`; no personal fields planned |
| `security create-keypair` prototype | No valid code-signing identity produced; rejected |
| `certtool` prototype | Certificate not accepted as a code-signing identity; rejected and cleaned up |
| Independent design review | Four rounds complete; no unresolved P0-P2 |
| Design-only release judgment | `none`; no tag or GitHub Release |

## Error Log

| Timestamp | Error | Attempt | Resolution |
| --- | --- | --- | --- |
| 2026-08-09 | 规划文件属于上一项已完成任务 | 1 | 重新初始化为本次签名与发布任务 |
| 2026-08-09 | 本机执行 `gh` 返回 command not found | 1 | 改用 GitHub REST/API；远程 Runner 内的 `gh` 发布步骤可继续保留 |
| 2026-08-09 | Web 工具拒绝直接打开 GitHub API URL | 1 | 改为搜索发现或只读 `curl`，不重复同一失败调用 |
| 2026-08-09 | 本机 Keychain 未找到 `SPARKLE_PRIVATE_KEY` | 1 | 保留已验证的 GitHub Secret 作为 appcast 签名源；设计阶段不读取或迁移私钥值 |
| 2026-08-09 | 临时文件清理命令被执行策略拒绝 | 1 | 改用纯管道读取证书公开元数据，没有生成或遗留证书文件 |
| 2026-08-09 | `security create-keypair` 返回 `0 valid identities found` | 1 | 删除临时钥匙串，改为验证带 Code Signing EKU 的证书方案 |
| 2026-08-09 | `certtool` 证书未被 `codesign` 识别，命令提前退出 | 1 | 立即移除临时证书信任、删除临时钥匙串并确认无残留 |
| 2026-08-09 | 设计遗漏 Runner 临时信任、Finder Automation 与恢复副本 | 1 | 接受独立 Review 的 1 项 P1、2 项 P2，并补充为强制发布门禁 |
| 2026-08-09 | 用户级 trust 可能弹窗、迁移步骤冲突、Sparkle 私钥无恢复副本 | 2 | 接受复审的 1 项 P1、2 项 P2，改为系统级临时 trust、全部权限恢复和加密恢复演练 |
| 2026-08-09 | 新增 GitHub Runner 文档链接的 `curl` 复查遇到临时 DNS 解析失败 | 1 | 已通过 Web 搜索读取 GitHub 官方文档并确认 passwordless `sudo`；提交前再重试链接检查 |
| 2026-08-09 | 恢复工作流允许替换收件公钥会形成 Secret 导出接口 | 3 | 接受第三次复审的 P2，固定公钥与指纹并加入 actor、Environment 审批和清理边界 |

## Next Step

- 提交并推送已通过独立 Review 的设计规格；用户确认后再修改生产实现。
