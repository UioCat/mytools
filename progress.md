# Progress Log

## Implementation update: 2026-08-09

- 开发包真实启动首次稳定复现 dyld `different Team IDs`：无 Team ID 的 Hardened Runtime 主程序无法加载 Sparkle。已只为主应用加入 `com.apple.security.cs.disable-library-validation`，嵌套组件不继承；重新打包后持续运行且无新增崩溃。
- 独立 Review 发现并推动修复 3 个 P2：按进程名误杀或误判、稳定/开发身份并发访问同一数据、开发包接入正式 Sparkle 渠道。开发包现为 `build/MacTools Dev.app`，无正式 feed/公钥，不启动更新器；另一身份运行时脚本立即失败。
- 签名清理复审继续发现并修复失败路径：系统信任使用写前 ownership marker，任何移除或验证不确定性都保留标记供重试；PEM/PKCS#12 在身份导入后立即删除，临时 Keychain/任务信任在 App 签名后立即退出；用户 Keychain 搜索列表通过 0600 原子快照精确恢复。fake `security`/`sudo` 故障回归覆盖早期失败、信任清理失败、查询失败和搜索列表读取失败。
- 最新开发包已通过真实打包、嵌套签名验证、启动和进程存活检查；明暗模式、`640 × 520` 紧凑窗口及权限整理确认框均完成视觉检查，没有边框、阴影或裁切阻断。
- 独立只读代码复审最终确认无未解决 P0-P3。发布判断为 `minor`，门禁全部通过后的建议版本为 `v0.4.0`。
- 本机已通过 Touch ID 完成固定公开证书的用户级 Code Signing 信任。稳定包使用固定 SHA-1 精确选择身份，已通过嵌套组件、证书指纹、DR 与隐私字段验证，原子安装到 `/Applications/MacTools.app` 后持续运行；任务级派生私钥、PKCS#12 和临时 Keychain 已清理。
- 稳定包权限页已真实执行仅限 `local.mactools.mvp` 的 `tccutil reset All`；重启后辅助功能、输入监控、自动粘贴和屏幕录制均显示未授权，其他应用授权未受影响。当前仍待人工删除旧裸可执行文件条目并启用新的正式 `MacTools.app` 条目。

- 签名 workflow 与脚本通过 `bash -n`、Ruby YAML 解析和 `git diff --check` 静态校验。
- 已通过本机 `127.0.0.1:7890` 代理修复 SwiftPM Sparkle 依赖；首次完整测试命中设置视图行数门禁，拆分视图后聚焦回归通过，随后完整套件已通过。
- 已接入按当前 Bundle ID 执行 `tccutil reset All` 的平台适配器、应用回前台权限刷新、权限页带确认的整理入口，以及稳定 `/Applications/MacTools.app` 与开发身份隔离的重建路径。
- 用户确认不使用 GitHub 页面的单根密钥方案：保留现有 `SPARKLE_PRIVATE_KEY`，通过 HKDF-SHA256 用途隔离派生 P-256 代码签名子密钥。
- 公开测试种子的派生原型已通过：同一输入重复得到同一标量和公钥指纹，生成的 SEC1 DER 可被 macOS 内置 OpenSSL 解析。
- push 触发的一次性恢复 workflow 已通过 Ruby YAML 解析、全部 `run` 块 `bash -n`、`git diff --check` 和 `ReleaseWorkflowSourceTests` 6 项聚焦回归。
- 恢复工作流首轮独立 Review 发现可变 `actions/checkout@v4` 的 P2 供应链风险和英文自动提交的 P3；已固定到官方完整 SHA、禁止持久化 checkout 凭据，并将写权限 token 限制在最后密文分支步骤，正在由同一 Agent 复审。
- 同一独立 Review Agent 复审确认恢复准备提交无 P0-P3；独立发布判断为 `none`。准备提交 `7d5bedb` 已推送 `main` 并通过专用分支触发。
- 远程成功产生 RSA-OAEP-SHA256 密文分支；本机解密后证明私钥种子为 44 字符/32 字节，导入 Sparkle Keychain 后公钥与现有 `SUPublicEDKey` 完全一致。触发分支和密文输出分支均已删除。
- 已从根种子派生正式 P-256 公钥，生成 2026-2046 年匿名证书；主题和签发者仅为 `MacTools Release Signing`，含 Code Signing EKU，没有姓名、邮箱或 Apple Team 字段。
- 新增派生脚本和自动化回归；最终签名、权限、打包、发布工作流和更新服务聚焦测试 39 项通过。
- 完整 `swift test` 通过 513 项，严格并发 `swift build --product MacTools -Xswiftc -strict-concurrency=complete -Xswiftc -warn-concurrency` 通过；所有当前 shell 脚本、workflow YAML、`run` 块语法和 `git diff --check` 均通过。
- 已精确删除早期原型在登录 Keychain 留下的旧 RSA 公共证书和两条临时密码记录，固定新证书及 Sparkle 根密钥保持不变；System.keychain 中同一旧原型公共证书仍待一次管理员授权后删除。

## Session: 2026-08-09

### Phase 1: Baseline & Design

- **Status:** complete
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
| 2026-08-09 | OpenSSL 默认 PKCS#12 导入报 `MAC verification failed` | 1 | 确认失败发生在临时身份导入；清理完成，改用 macOS 兼容的 SHA-1/3DES PKCS#12 参数重试 |
| 2026-08-09 | 原型环境中 `codesign` 不能用临时证书 SHA-1 直接选取身份 | 2 | 先以名称完成原型定位；信任配置完成后 SHA-1 精确选择验证成功并成为最终方案，签名后继续严格比对实际指纹和 DR |
| 2026-08-09 | 用户级 `security add-trusted-cert` 等待认证并留下挂起进程 | 3 | 精确终止两个原型进程，删除临时钥匙串/文件并确认无 trust 残留；本机原型改用临时系统级信任或隔离 Keychain Access 路径 |
| 2026-08-09 | 正式身份导入时默认钥匙串路径含缩进，`security import` 报找不到钥匙串 | 1 | 身份尚未导入且临时文件已清理；改为去除引号与首尾空白后重试 |
| 2026-08-09 | 原型命令中的 `rm -rf` 被执行策略拒绝 | 1 | 未执行或删除任何内容；改用精确 `mktemp` 路径、`unlink` 和 `rmdir` 重试并完成清理 |
| 2026-08-09 | 系统 Ruby 2.6 的 `YAML.load_file` 不支持 `aliases:` 关键字 | 1 | 该 workflow 不使用 YAML alias，改用兼容的 `YAML.load_file(path)` 后解析和 shell 语法校验通过 |
| 2026-08-09 | 自动提交的多行 shell 字符串缩进不符合 YAML block scalar | 1 | Ruby 解析在进入 shell 前即失败；补齐两行 YAML 缩进后解析、`bash -n` 和聚焦测试均通过 |
| 2026-08-09 | `openssl x509` 一次调用不接受同时指定 `-sha1 -sha256` | 1 | 命令在指纹输出前失败；拆成两次独立调用后指纹与脚本固定值均匹配 |
| 2026-08-09 | EC 私钥和证书分开导入临时 Keychain 后 `find-identity` 为 0 | 1 | 证书存在但未形成可签名配对；改为临时加密 PKCS#12 导入，`security export -t identities` 可导出完整身份 |
| 2026-08-09 | OpenSSL 3 默认不解析 macOS `security export` 的 RC2-40-CBC PKCS#12 | 1 | 身份导出已成功；验证命令增加 `-legacy` 后配对校验通过 |
| 2026-08-09 | 首次用 AppleScript 打开可见 Terminal 的嵌套引号语法错误 | 1 | 未执行 sudo 或修改系统；移除多余的完成文案嵌套后成功打开独立 Terminal 命令 |
| 2026-08-09 | 未信任的 P-256 Keychain identity 无法签名临时 `/usr/bin/true` 副本 | 1 | 返回状态 1，且临时副本已精确删除；证明系统级 `codeSign` 信任是签名前必需门禁，继续等待人工管理员认证 |
| 2026-08-09 | 首次真实开发包在启动时被 dyld 以 `different Team IDs` 拒绝加载 Sparkle | 1 | 崩溃报告定位到无 Team ID 下的 Library Validation；主应用加入唯一最小例外并重新打包启动通过 |
| 2026-08-09 | 开发打包在 `codesign -dv | grep -q` 处因 `pipefail` 返回 141 | 1 | 改为先捕获完整输出再匹配，并清理其他签名检查中的同类早退管道 |
| 2026-08-09 | 开发包移除 `SUFeedURL` 后 Sparkle 启动时显示英文错误框 | 1 | `SystemUpdateService` 检测无 feed 时不创建更新器，软件更新状态保持禁用且重新打包启动无弹框 |

## Next Step

- 完成正式权限单条目整理、最终独立复审、第二台 Mac 恢复演练、低构建号真实更新和 GitHub Runner preflight；全部发布门禁通过后再创建版本标签。

### Phase 2: Implementation

- **Status:** in_progress
- Actions taken:
  - 用户确认书面设计并授权开始实现。
  - 记录实现基线：`main@a0cf547`，工作树干净。
  - 加载 macOS 调试、SwiftUI 设置和完成前验证指南。
  - 匿名证书隔离原型首次在 PKCS#12 导入阶段失败；清理 trap 已删除临时钥匙串、文件和信任。
  - 兼容 PKCS#12 导入成功，`security find-identity` 找到有效匿名身份；原型环境的 SHA-1 选择失败用于定位信任问题，完成信任配置后已验证 SHA-1 精确选择并作为最终方案。
  - 证书名称原型卡在用户级 trust 认证；已终止挂起进程并确认临时目录、钥匙串和信任无残留。
