# Task Plan: 匿名稳定签名、多机权限与 GitHub Release

## Goal

在没有付费 Apple Developer Program 的前提下，为用户自己的多台 Mac 建立不包含个人身份的固定自签名身份、单一发布产物和可验证的 GitHub Release 流程，使后续版本不再因 ad-hoc 重建产生重复的 MacTools 权限项。

## Current Phase

Design

## Phases

### Phase 1: Baseline & Design
- [x] 记录 `main@c4b637a`、`v0.3.0` 和干净工作树基线
- [x] 确认现有 GitHub Actions 强制 ad-hoc 重建
- [x] 比较 Apple Development、固定匿名自签名和继续 ad-hoc 三种方案
- [x] 确认公开 Release 不接受暴露姓名与邮箱
- [x] 写入并完成独立设计 Review，自审无未解决 P0-P2
- [ ] 用户确认书面设计规格
- **Status:** in_progress

### Phase 2: Implementation
- [ ] 收紧打包脚本，稳定渠道禁止静默回退 ad-hoc
- [ ] 建立固定匿名代码签名身份并安全写入本机 Keychain 与 GitHub Actions Secret
- [ ] 在第二台个人 Mac 的 Keychain 导入恢复身份并完成签名演练
- [ ] 加密恢复现有 Sparkle EdDSA 私钥并在两台个人 Mac 的 Keychain 完成恢复演练
- [ ] 调整远程工作流为导入匿名身份、构建并验证唯一发布产物
- [ ] 统一正式运行路径并提供一次性旧权限清理引导
- [ ] 权限设置页在应用重新激活时刷新真实状态
- [ ] 更新自动化测试、README 和人工验收清单
- **Status:** pending

### Phase 3: Verification & Review
- [ ] 聚焦测试、完整 `swift test`、严格并发检查和打包验证
- [ ] 多路径、签名 requirement、DMG、SHA-256、appcast 与敏感信息扫描
- [ ] 独立代码 Review 清零 P0-P2
- [ ] 独立发布判断确认版本级别、完整发布范围和门禁
- **Status:** pending

### Phase 4: Commit, Push & Release
- [ ] 仅提交本任务改动并推送 `origin/main`
- [ ] 计算下一版本并完成较低构建号更新发现验证
- [ ] 创建带注释标签并持续等待发布工作流
- [ ] 核验公开 Release、DMG、校验和、appcast 与 latest 地址
- [ ] 同一发布判断 Agent 完成发布后复核
- **Status:** pending

## Decisions Made

| Decision | Rationale |
| --- | --- |
| 不采用 Developer ID | 用户没有付费 Apple Developer Program |
| 不公开使用 Apple Development | 证书会暴露真实姓名、邮箱和 Apple 标识 |
| 采用固定匿名自签名身份 | 仅公开项目名、证书指纹和有效期，同时提供跨版本稳定 DR |
| 多台 Mac 安装同一个 Release 产物 | 避免不同机器或路径产生新的代码身份 |
| 每台 Mac 单独授予 TCC 权限 | 系统权限不跨设备同步 |
| 私钥不写入仓库或普通文件 | 签名身份属于敏感资产 |

## Errors Encountered

| Error | Attempt | Resolution |
| --- | --- | --- |
| 规划文件仍是上一项已完成任务 | 1 | 切换为本次签名与发布任务，旧结论仍保留在 Git 历史和对应设计文档 |
| 本机没有 `gh` CLI | 1 | 设计和实现不依赖本机 `gh`；标签触发的 Runner 继续使用内置 `gh`，本机用 GitHub REST/API 和 Git 检查发布状态 |
| Web 工具拒绝直接打开 GitHub API URL | 1 | 后续先用搜索发现安全页面，或使用只读 `curl` 获取公开 API；不重复直接 open |
| 本机 Keychain 未找到 `SPARKLE_PRIVATE_KEY` 通用密码项 | 1 | 现有 GitHub Secret 已由 v0.3.0 成功工作流验证；设计改为远程生成 appcast，或另行安全配置本机 Keychain |
| 含 `rm -f` 的临时证书检查被执行策略拒绝 | 1 | 不创建临时文件，改用 `security find-certificate | openssl x509` 管道只读检查 |
| `security create-keypair` 只生成密钥对，没有可用于代码签名的证书身份 | 1 | 删除临时钥匙串；不将该命令作为身份生成方案 |
| `certtool` 生成的旧式自签名证书不被 `codesign` 识别为有效身份 | 1 | 移除临时信任和钥匙串；设计改用带 Code Signing EKU 的自签名证书并在实现阶段先做隔离原型 |
| 独立 Review 指出 Runner 信任、Finder Automation 迁移和密钥恢复缺口 | 1 | 将临时 codeSign 信任、Bundle ID 级 `All` 重置及第二台 Mac Keychain 恢复演练加入发布门禁 |
| 复审指出用户级信任不可无人值守、迁移步骤不一致且 Sparkle 私钥无恢复副本 | 2 | 改为 passwordless `sudo` 系统级临时信任；补齐全部权限恢复；增加公钥加密的 Secret 恢复流程和双机演练 |
| 第三次复审指出可变恢复公钥会形成 Secret 导出接口 | 3 | 将一次性公钥和指纹固定到受审提交，限定仓库所有者和受保护 Environment 审批，不接受 dispatch 公钥输入 |

## Notes

- 设计确认前不修改生产代码、打包脚本或工作流。
- 当前公开发布使用 ad-hoc；匿名自签名仍无法获得 Developer ID 公证，首次下载后每台 Mac 需要确认一次“仍要打开”。
