# MacTools GitHub Release 发布指南

本文用于维护者发布 MacTools 稳定版本。正式发布入口只有一个：向 GitHub 推送指向已验证 `main` 提交的 `vX.Y.Z` 标签，由 GitHub Actions 自动构建并发布 Release。不要在 GitHub 页面手工拼装正式 Release。

```text
main 最终提交
  → 本地测试与运行时验证
  → 匿名签名预检
  → 发布判断与标签前检查
  → 推送 vX.Y.Z 标签
  → 构建并验证正式 App
  → 生成 DMG、SHA-256、签名 appcast
  → 公开 GitHub Release
  → 回读公开资产并复核更新源
```

## 当前发布约定

| 项目 | 当前约定 |
| --- | --- |
| 发布分支 | 仅 `main` 可以自动发布；其他分支只给出版本建议 |
| 标签格式 | `vX.Y.Z`，版本包含一至三段数字；`X ≤ 8999`、`Y/Z ≤ 99`，例如 `v0.4.2` |
| 目标平台 | macOS 26 及以上、Apple Silicon `arm64` |
| 应用标识 | `local.mactools.mvp` |
| 代码签名 | 固定匿名证书 `MacTools Release Signing`，不是 Developer ID，也不包含 Apple Team ID |
| 更新签名 | Sparkle EdDSA；根私钥只保存在 GitHub Actions Secret 和维护者恢复 Keychain 中 |
| 更新源 | `https://github.com/UioCat/mytools/releases/latest/download/appcast.xml` |
| Release 资产 | DMG、DMG 的 SHA-256 文件、经 EdDSA 签名的 `appcast.xml` |

固定匿名签名用于保持后续版本的应用身份，不能替代 Apple Developer ID 和公证。每台 Mac 首次安装时仍可能需要在“系统设置 → 隐私与安全性”中确认打开。

## 关键文件与凭据

| 路径或配置 | 作用 |
| --- | --- |
| `.github/workflows/signing-preflight.yml` | owner-only 匿名签名预检，不创建标签和 Release |
| `.github/workflows/release.yml` | 监听 `v*` 标签，构建、签名并发布 GitHub Release |
| `scripts/package_app.sh` | 通过 SwiftPM 构建并组装、签名正式应用包 |
| `scripts/create_dmg.sh` | 生成压缩 DMG 和 SHA-256 文件 |
| `scripts/macos_build_number.sh` | 从公开语义版本确定性生成内部构建号 |
| `scripts/ci/import_anonymous_signing_identity.sh` | 从发布根密钥派生 P-256 代码签名私钥并导入临时 Keychain |
| `scripts/ci/cleanup_anonymous_signing_identity.sh` | 清理临时 Keychain、证书信任和敏感文件 |
| GitHub Secret `SPARKLE_PRIVATE_KEY` | Sparkle EdDSA 签名根密钥，也是用途隔离的匿名代码签名派生根 |

不得把 `SPARKLE_PRIVATE_KEY`、派生私钥、PKCS#12、Keychain 密码或 Authorization 信息写入仓库、普通文件、日志或 Release 资产。公开证书、公钥和指纹不是秘密，但不得在未设计迁移方案时替换。

## 1. 判断是否需要发布

先只评估当前任务产生的改动，再评估从 GitHub 最新稳定 Release 到候选提交的完整未发布范围。

| 变化类型 | 版本级别 | 动作 |
| --- | --- | --- |
| 可复现的用户可感知 Bug 修复，或有量化、可重复验证证据的兼容性、性能、资源或稳定性优化 | `patch` | 递增补丁版本 |
| 新增用户可感知功能，或较大的向后兼容行为变化 | `minor` | 递增次版本 |
| 仅文档、测试、内部重构、CI、开发工具改动，或缺少客观验证证据的优化 | `none` | 只提交和推送，不单独发布 |
| 疑似破坏性变更 | `major` 待确认 | 停止自动发布，先取得明确确认 |

发布判断必须由独立只读角色完成，并固定给出：`是否需要发布`、`版本级别`、`用户可感知依据`、`验证证据` 和 `发布阻断项`。存在来源不明的未发布提交、影响无法确认或验证证据不足时，不得创建标签。

查看当前最新稳定版本：

```sh
git fetch origin --prune --tags
gh release view --json tagName,isDraft,isPrerelease,publishedAt,url
```

内部构建号不需要人工填写，由公开版本自动计算：

```text
CFBundleShortVersionString = X.Y.Z
CFBundleVersion            = (1000 + X).Y.Z
```

例如 `v0.4.2` 对应公开版本 `0.4.2` 和内部构建号 `1000.4.2`。内部构建号用于 Sparkle 单调比较，不在设置页展示。

## 2. 完成发布前验证

### 2.1 Git 与改动范围

发布候选必须满足：

- 当前分支为 `main`；
- 候选提交已经推送，且本地 `HEAD` 与 `origin/main` 完全一致；
- 当前任务没有未提交文件，任务外已有改动已经明确隔离；
- GitHub 最新稳定 Release 标签是候选提交的祖先；
- 目标版本标签和 Release 均不存在；
- 目标提交没有正在运行或失败待处理的发布工作流。

```sh
git fetch origin --prune --tags

test "$(git branch --show-current)" = main
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
test -z "$(git status --porcelain)"

LATEST_TAG="$(gh release view --json tagName --jq .tagName)"
git merge-base --is-ancestor "$LATEST_TAG" HEAD
```

如果主工作树存在明确不属于发布候选的本地改动，应使用干净 clone 或 detached worktree 完成最终验证和打标签，禁止把无关改动夹带进提交。

### 2.2 测试、打包与运行时

按改动风险先窄后宽执行：

```sh
# 与改动直接相关的聚焦测试
swift test --filter <TestCaseName>

# 完整单元测试
swift test

# 开发签名的真实 App Bundle
MACOS_SIGNING_MODE=development scripts/package_app.sh

# 基础脚本和差异检查
bash -n scripts/package_app.sh
bash -n scripts/create_dmg.sh
bash -n scripts/signing/derive_anonymous_signing_private_key.sh
git diff --check
```

根据改动范围补充 `AGENTS.md` 和 `docs/manual-verification.md` 规定的 UI、权限、Finder、截图录屏、严格并发或真实打包应用检查。软件更新或发布改动至少需要使用较低版本正式包确认：

1. 可以发现当前稳定 Release；
2. 展示的版本和中文提示正确；
3. DMG 下载和 EdDSA 校验成功；
4. 安装并重启后版本正确；
5. 固定应用身份及相关系统权限没有异常漂移。

完成独立代码 Review；确认没有未解决的 P0、P1 或 P2。发布脚本、签名、软件更新或工作流变化即使文件很少，也必须执行该 Review。

### 2.3 敏感信息扫描

```sh
rg -n --hidden \
  --glob '!.git/**' \
  --glob '!.worktrees/**' \
  --glob '!.build/**' \
  --glob '!build/**' \
  --glob '!log/**' \
  -i 'api[_ -]?key|access[_ -]?key|secret|token|password|credential|private[_ -]?key|client[_ -]?secret|app[_ -]?secret|authorization|bearer|cookie|session'
```

关键词命中必须结合上下文人工复核。字段名、公开证书信息和测试占位值可以保留；真实密钥、用户数据和运行时日志必须在提交前移除。

## 3. 运行匿名签名预检

最终候选形成后，先把同一个提交推送到 owner-only 预检分支。该工作流不会创建标签或 Release。

```sh
CANDIDATE_SHA="$(git rev-parse HEAD)"
git push origin "$CANDIDATE_SHA:refs/heads/codex/anonymous-signing-preflight"
```

预检分支必须能安全快进。如果远端分支发生异常分叉，停止并检查来源，不要直接强制推送。

查找并持续等待精确候选的预检：

```sh
gh run list \
  --workflow 'Anonymous signing preflight' \
  --limit 10 \
  --json databaseId,headSha,status,conclusion,url

gh run watch <RUN_ID> --exit-status

gh run view <RUN_ID> \
  --json headSha,status,conclusion,url
```

预检成功必须同时证明：

| 阶段 | 必须通过的检查 |
| --- | --- |
| 首台 GitHub Runner | 派生固定身份、构建稳定 App、删除普通私钥和 PKCS#12、退役临时 Keychain、上传短期产物 |
| 第二台全新 Runner | 证书保持系统不信任、深度严格签名有效、Authority 与固定证书 leaf 哈希匹配、不是 ad-hoc/Apple Development/Developer ID |

预检成功记录必须对应最终候选 SHA。候选提交变化后，旧的预检结果立即失效，必须重新执行。

## 4. 创建并推送发布标签

只有发布判断无阻断、所有验证通过且预检对应最终 SHA 时，才能创建标签。

```sh
VERSION=0.4.2 # 示例：发布前改为下一个目标版本，不含 v 前缀
CANDIDATE_SHA="$(git rev-parse HEAD)"
if ! BUILD_NUMBER="$(scripts/macos_build_number.sh "$VERSION")"; then
  echo "目标版本不满足发布规则：$VERSION" >&2
  exit 1
fi

test "$(git branch --show-current)" = main
test "$CANDIDATE_SHA" = "$(git rev-parse origin/main)"
test -z "$(git status --porcelain)"
test -n "$BUILD_NUMBER"

if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  echo "目标标签已存在：v$VERSION" >&2
  exit 1
fi

if gh release view "v$VERSION" >/dev/null 2>&1; then
  echo "目标 Release 已存在：v$VERSION" >&2
  exit 1
fi

git tag -a "v$VERSION" "$CANDIDATE_SHA" \
  -m "发布 MacTools v$VERSION" \
  -m "填写本版本面向用户的主要变化。"

test "$(git rev-list -n 1 "v$VERSION")" = "$CANDIDATE_SHA"
git push origin "refs/tags/v$VERSION"
```

标签推送是正式发布的不可逆起点。推送前再次核对版本号和 SHA；标签推送后不得自动删除、移动或覆盖标签。

## 5. 等待 GitHub Actions 发布

标签会触发 `.github/workflows/release.yml`。查找目标版本运行并持续等待：

```sh
gh run list \
  --workflow 'Release macOS DMG' \
  --limit 10 \
  --json databaseId,headBranch,headSha,status,conclusion,url

gh run watch <RUN_ID> --exit-status
```

工作流包含两个阶段：

### 构建正式应用

1. 从标签解析公开版本和内部构建号；
2. 从 `SPARKLE_PRIVATE_KEY` 用途隔离派生 P-256 签名子私钥；
3. 在临时 Keychain 中导入固定匿名证书；
4. 通过 SwiftPM 构建 `arm64` Release，并由内到外签名 Sparkle 组件和主应用；
5. 清理临时签名身份，再上传保留一天的内部 App 构建产物。

### 制作并公开 Release

1. 第二台全新 Runner 下载 App 并验证版本、架构、固定证书、签名和 Sparkle 配置；
2. 生成 `MacTools-vX.Y.Z-arm64-macos26.dmg` 和 SHA-256 文件；
3. 只读挂载 DMG，重新检查应用和 `/Applications` 快捷方式；
4. 根据上一个版本标签到当前提交的 Git 日志生成中文 Release Notes；
5. 生成并验证带 EdDSA 签名的 `appcast.xml`；
6. 创建草稿 Release，上传三个资产，全部成功后转为公开；
7. 从公开 Release 回读资产并验证 `latest` appcast。

任一阶段失败都不能宣称发布完成。不要移动或删除已推送标签，也不要覆盖已公开 Release；先保留失败证据，修复后重新评估版本号和发布范围。

## 6. 发布后独立复核

不能只看 GitHub Actions 的绿色状态。必须从公开 Release 重新下载资产验证，并由同一个独立发布判断角色完成发布后只读复核。

### 6.1 Release 状态和资产

```sh
VERSION=0.4.2 # 示例：发布前改为目标版本，不含 v 前缀

gh release view "v$VERSION" \
  --json tagName,isDraft,isPrerelease,publishedAt,url,assets
```

必须确认 Release 非草稿、非预发布，并且包含且只包含本流程要求的三个发布资产：

```text
MacTools-vX.Y.Z-arm64-macos26.dmg
MacTools-vX.Y.Z-arm64-macos26.dmg.sha256
appcast.xml
```

### 6.2 DMG 和 appcast

```sh
VERSION=0.4.2 # 示例：发布前改为目标版本，不含 v 前缀
VERIFY_DIR="$(mktemp -d "${TMPDIR%/}/mactools-release-public.XXXXXX")"
DMG_NAME="MacTools-v$VERSION-arm64-macos26.dmg"

gh release download "v$VERSION" \
  --dir "$VERIFY_DIR" \
  --pattern "$DMG_NAME" \
  --pattern "$DMG_NAME.sha256" \
  --pattern appcast.xml

(
  cd "$VERIFY_DIR"
  shasum -a 256 -c "$DMG_NAME.sha256"
  hdiutil verify "$DMG_NAME"
  xmllint --noout appcast.xml
  grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" appcast.xml
  grep -q 'sparkle:edSignature=' appcast.xml
  grep -q '<!-- sparkle-signatures:' appcast.xml
)
```

必须使用维护者恢复 Keychain 中的同一 Sparkle 根密钥验证公开 appcast feed 的密码学签名。当前账户名为 `UioCat.mytools`：

```sh
swift package resolve

.build/artifacts/sparkle/Sparkle/bin/sign_update \
  --account UioCat.mytools \
  --verify \
  "$VERIFY_DIR/appcast.xml"
```

`sign_update --verify` 必须成功。Keychain 中不存在已演练的同一根密钥、账户不匹配或验签失败时，均应阻断发布完成状态；XML 可解析以及签名字段存在不能替代密码学验签。

下载 `latest` appcast 并进行逐字节比较：

```sh
curl --fail --location --retry 3 \
  'https://github.com/UioCat/mytools/releases/latest/download/appcast.xml' \
  --output "$VERIFY_DIR/latest-appcast.xml"

cmp "$VERIFY_DIR/appcast.xml" "$VERIFY_DIR/latest-appcast.xml"
```

最后只读挂载 DMG，并再次检查：

- `codesign --verify --deep --strict` 通过；
- Authority 为 `MacTools Release Signing`，固定证书指纹和 designated requirement 匹配；
- `CFBundleShortVersionString`、`CFBundleVersion` 和 appcast 完全一致；
- `CFBundleDevelopmentRegion` 与 `CFBundleLocalizations` 为 `zh_CN`；
- Sparkle 更新源、公钥和签名强制配置存在；
- 使用较低稳定版本可以发现、下载、安装并重启到新版本。

所有证据通过后，发布状态才是“完成”。

## 常见阻断与处理

| 现象 | 处理 |
| --- | --- |
| `main` 与 `origin/main` 不一致 | 停止发布，先拉取、审查并完成合并，不要给旧提交打标签 |
| 目标标签或 Release 已存在 | 停止；确认是否已经发布，禁止覆盖或移动稳定标签 |
| `SPARKLE_PRIVATE_KEY` 缺失或公钥不匹配 | 阻断发布；从已演练恢复 Keychain 恢复同一密钥，不要生成新密钥代替 |
| 匿名签名预检失败 | 检查精确 SHA、Runner、临时 Keychain、证书指纹和清理步骤；修复后重新预检 |
| 工作流在标签推送后失败 | 保留标签和失败证据，不自动删除标签；重新评估修复与下一个版本 |
| DMG 校验和不一致 | 视为资产损坏，阻断完成状态，不手工替换公开文件掩盖问题 |
| appcast EdDSA 验证失败 | 阻断发布和自动更新；检查 Secret、签名工具和发布资产是否来自同一候选 |
| `latest` appcast 尚未收敛 | 等待并重试；未与当前 Release 资产逐字节一致前不得结束发布 |
| 首次安装被 Gatekeeper 阻止 | 当前匿名签名的预期边界；通过“隐私与安全性”确认，不得宣称已完成 Apple 公证 |

## 发布完成记录模板

```markdown
## MacTools vX.Y.Z 发布结果

- 候选提交：`<full-sha>`
- 目标分支：`main`
- 发布判断：`patch` / `minor`
- 独立 Review：无未解决 P0～P2
- 聚焦测试：通过
- 完整测试：`N/N` 通过
- 匿名签名预检：`<run-url>`
- Release 工作流：`<run-url>`
- GitHub Release：`<release-url>`
- DMG SHA-256：`<sha256>`
- App 版本 / 构建号：`X.Y.Z / (1000 + X).Y.Z`
- Appcast EdDSA：通过
- Latest appcast：与 Release 资产逐字节一致
- 较低版本真实更新：通过
- 剩余阻断项：无
```
