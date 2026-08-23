# MacTools 发布步骤

本文是 MacTools 唯一的版本发布步骤清单。正式发布只通过一个入口完成：向 GitHub 推送指向已验证 `main` 提交的 `vX.Y.Z` 标签，由 `.github/workflows/release.yml` 自动构建、签名并公开 Release。

## 发布边界

| 项目 | 约定 |
| --- | --- |
| 发布分支 | 只发布 `main`；其他分支只提交代码，不创建版本标签 |
| 标签 | 带注释的 `vX.Y.Z`，例如 `v0.5.1` |
| 架构 | macOS 26 及以上、Apple Silicon `arm64` |
| 应用标识 | `local.mactools.mvp` |
| Release 资产 | DMG、对应 SHA-256 文件、经 EdDSA 签名的 `appcast.xml` |
| 更新源 | `https://github.com/UioCat/mytools/releases/latest/download/appcast.xml` |
| 私钥 | 只允许位于 GitHub Actions Secret `SPARKLE_PRIVATE_KEY` 和维护者 Keychain |

固定匿名代码签名用于保持 MacTools 跨版本身份，不等同于 Apple Developer ID 或 Apple 公证。Sparkle EdDSA 用于验证更新资产来源，两者不能互相替代。

## 标准发布流程

日常版本发布只执行以下四步。除“条件验证”明确命中的项目外，不增加分支预检、浏览器下载产物或重复构建。

### 1. 确认候选提交

发布前必须确认：

- 当前分支是 `main`，工作树干净；
- 候选提交已推送，`HEAD` 与 `origin/main` 完全一致；
- 最新稳定 Release 标签是候选提交的祖先；
- 目标标签和目标 Release 不存在；
- 当前发布范围没有来源不明的提交和未解决的 P0～P2。

```sh
VERSION=0.5.1 # 示例，不含 v 前缀
TAG="v$VERSION"

git fetch origin --prune --tags
test "$(git branch --show-current)" = main
test -z "$(git status --porcelain)"
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
scripts/macos_build_number.sh "$VERSION"
test -z "$(git tag --list "$TAG")"

LATEST_RELEASE="$(curl --fail --silent --show-error \
  https://api.github.com/repos/UioCat/mytools/releases/latest)"
LATEST_TAG="$(jq -r .tag_name <<<"$LATEST_RELEASE")"
LATEST_PUBLISHED_AT="$(jq -r .published_at <<<"$LATEST_RELEASE")"
git merge-base --is-ancestor "$LATEST_TAG" HEAD
awk -v target="$VERSION" -v latest="${LATEST_TAG#v}" '
  function version_number(value, parts) {
    split(value, parts, ".")
    return (parts[1] * 10000) + (parts[2] * 100) + parts[3]
  }
  BEGIN { exit !(version_number(target) > version_number(latest)) }
'

test "$(curl --silent --output /dev/null --write-out '%{http_code}' \
  "https://api.github.com/repos/UioCat/mytools/releases/tags/$TAG")" = 404

RELEASE_RUNS="$(curl --fail --silent --show-error \
  'https://api.github.com/repos/UioCat/mytools/actions/workflows/release.yml/runs?per_page=30')"
jq -e '[.workflow_runs[] | select(.status != "completed")] | length == 0' \
  <<<"$RELEASE_RUNS"
jq -e --arg published "$LATEST_PUBLISHED_AT" '
  [.workflow_runs[] | select(
    .created_at > $published and
    (.conclusion == "failure" or
     .conclusion == "cancelled" or
     .conclusion == "timed_out" or
     .conclusion == "action_required" or
     .conclusion == "startup_failure" or
     .conclusion == "stale")
  )] | length == 0
' <<<"$RELEASE_RUNS"
```

发布范围需要独立只读判断，并输出：`是否需要发布`、`版本级别`、`用户可感知依据`、`验证证据` 和 `发布阻断项`。

| 变化 | 版本级别 |
| --- | --- |
| 用户可感知 Bug 修复，或有客观证据的兼容性、性能、资源、稳定性优化 | `patch` |
| 新增用户功能，或较大的向后兼容行为变化 | `minor` |
| 仅文档、测试、内部重构、CI 或开发工具 | `none`，不发布 |
| 疑似破坏性变化 | 停止，确认主版本策略 |

### 2. 执行发布前验证

每次发布固定执行：

```sh
# 直接相关的聚焦测试
swift test --filter <TestCaseName>

# 完整测试
swift test

# 构建真实 App Bundle；开发签名不依赖发布私钥
MACOS_SIGNING_MODE=development scripts/package_app.sh

# 文本与敏感信息检查
git diff --check
rg -n --hidden \
  --glob '!.git/**' \
  --glob '!.worktrees/**' \
  --glob '!.build/**' \
  --glob '!build/**' \
  --glob '!log/**' \
  -i 'api[_ -]?key|access[_ -]?key|secret|token|password|credential|private[_ -]?key|client[_ -]?secret|app[_ -]?secret|authorization|bearer|cookie|session'
```

关键词命中需要结合上下文检查；字段名、公开证书和测试占位值可以保留，真实密钥、用户数据和运行时日志不能进入提交。

根据本次发布范围执行下表中的条件验证：

| 改动范围 | 必须增加的验证 |
| --- | --- |
| Actor、Task、Timer、AsyncStream 或共享状态 | 严格并发构建，并检查取消、代际、释放和主线程阻塞 |
| UI、权限、Finder、截图录屏、自动粘贴或快捷键 | 按 `docs/manual-verification.md` 使用打包应用验证受影响场景 |
| iCloud、SQLite、缓存、剪贴板载荷或设置迁移 | 验证旧数据兼容、事务回退及受影响的真实运行时场景；不得修改用户生产数据来制造测试条件 |
| Sparkle、代码签名、打包脚本、发布工作流或发布证书 | 运行匿名签名预检，并用较低稳定版本完成发现、下载、安装和重启验证 |
| 普通业务代码，且上述发布链路未变化 | 不运行匿名签名预检，不下载 Actions 临时产物，不重复验证低版本更新 |

匿名签名预检只验证发布身份的派生、签名、清理和跨 Runner 完整性。它不创建 Release，也不替代正式标签工作流。需要执行时，将最终候选推送到预检分支并等待对应 SHA 成功：

```sh
CANDIDATE_SHA="$(git rev-parse HEAD)"
git push origin "${CANDIDATE_SHA}:refs/heads/codex/anonymous-signing-preflight"

# 重复查询，直到精确候选 SHA 的运行完成；只有 success 可以继续
PREFLIGHT_RUNS="$(curl --fail --silent --show-error \
  'https://api.github.com/repos/UioCat/mytools/actions/workflows/signing-preflight.yml/runs?per_page=10')"
jq -e --arg sha "$CANDIDATE_SHA" '
  [.workflow_runs[] | select(.head_sha == $sha)] | first |
  .status == "completed" and .conclusion == "success"
' <<<"$PREFLIGHT_RUNS"
```

候选提交变化后旧预检失效。无需把预检产物下载到本机；只有排查工作流失败时才打开 Actions 页面或下载临时 Artifact。

### 3. 创建并推送标签

所有必需验证通过后，直接创建并推送标签：

测试和人工验证可能持续较长时间，因此不得复用步骤 1 保存的远端结果。创建标签前必须重新获取远端状态，并重新执行候选、版本、Release 和 Actions 检查：

```sh
VERSION=0.5.1 # 示例，不含 v 前缀
TAG="v$VERSION"

git fetch origin --prune --tags
CANDIDATE_SHA="$(git rev-parse HEAD)"
test "$(git branch --show-current)" = main
test -z "$(git status --porcelain)"
test "$CANDIDATE_SHA" = "$(git rev-parse origin/main)"
printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
scripts/macos_build_number.sh "$VERSION"
test -z "$(git tag --list "$TAG")"

LATEST_RELEASE="$(curl --fail --silent --show-error \
  https://api.github.com/repos/UioCat/mytools/releases/latest)"
LATEST_TAG="$(jq -r .tag_name <<<"$LATEST_RELEASE")"
LATEST_PUBLISHED_AT="$(jq -r .published_at <<<"$LATEST_RELEASE")"
git merge-base --is-ancestor "$LATEST_TAG" HEAD
awk -v target="$VERSION" -v latest="${LATEST_TAG#v}" '
  function version_number(value, parts) {
    split(value, parts, ".")
    return (parts[1] * 10000) + (parts[2] * 100) + parts[3]
  }
  BEGIN { exit !(version_number(target) > version_number(latest)) }
'
test "$(curl --silent --output /dev/null --write-out '%{http_code}' \
  "https://api.github.com/repos/UioCat/mytools/releases/tags/$TAG")" = 404

RELEASE_RUNS="$(curl --fail --silent --show-error \
  'https://api.github.com/repos/UioCat/mytools/actions/workflows/release.yml/runs?per_page=30')"
jq -e '[.workflow_runs[] | select(.status != "completed")] | length == 0' \
  <<<"$RELEASE_RUNS"
jq -e --arg published "$LATEST_PUBLISHED_AT" '
  [.workflow_runs[] | select(
    .created_at > $published and
    (.conclusion == "failure" or
     .conclusion == "cancelled" or
     .conclusion == "timed_out" or
     .conclusion == "action_required" or
     .conclusion == "startup_failure" or
     .conclusion == "stale")
  )] | length == 0
' <<<"$RELEASE_RUNS"

git tag -a "$TAG" "$CANDIDATE_SHA" \
  -m "发布 MacTools $TAG" \
  -m "填写本版本面向用户的主要变化。"

test "$(git rev-list -n 1 "$TAG")" = "$CANDIDATE_SHA"
git push origin "refs/tags/$TAG"
```

标签推送是正式发布的起点。推送后不得删除、移动或覆盖标签。

### 4. 等待并核验 Release

标签触发 `Release macOS DMG` 工作流。持续等待目标 tag 对应运行结束，不因中间步骤耗时而重复创建标签。

重复执行以下检查，直到精确 tag 和候选 SHA 的运行完成；只有 `success` 可以继续发布后核验：

```sh
RELEASE_RUNS="$(curl --fail --silent --show-error \
  'https://api.github.com/repos/UioCat/mytools/actions/workflows/release.yml/runs?per_page=10')"
jq -e --arg tag "$TAG" --arg sha "$CANDIDATE_SHA" '
  [.workflow_runs[] | select(.head_branch == $tag and .head_sha == $sha)] | first |
  .status == "completed" and .conclusion == "success"
' <<<"$RELEASE_RUNS"
```

工作流会自动完成：

1. 构建 `arm64` 正式 App，并签名 Sparkle 组件和主应用；
2. 在全新 Runner 验证应用版本、架构、固定证书和签名；
3. 生成并验证 DMG 与 SHA-256；
4. 生成并验证 EdDSA 签名的 `appcast.xml`；
5. 公开 GitHub Release；
6. 从公开地址回读资产，并验证 `latest` appcast。

工作流成功后只需确认：

- Release 非草稿、非预发布，tag 和候选提交一致；
- 资产只有 `MacTools-vX.Y.Z-arm64-macos26.dmg`、对应 `.sha256` 和 `appcast.xml`；
- 工作流的公开资产回读、校验和、appcast 验签和 `latest` 比对步骤全部成功；
- 同一独立只读角色复核上述公开证据，没有剩余阻断项。

只有发布链路本身发生变化时，才额外从公开 Release 下载资产并在本机重复验签和低版本安装。普通 Bug 修复发布不重复执行 GitHub Actions 已经完成的验证。

## 失败处理

| 现象 | 处理 |
| --- | --- |
| 标签推送前任一必需验证失败 | 不创建标签；修复并重新验证 |
| 标签推送后工作流失败 | 保留标签和失败证据，不删除或移动标签；修复后重新判断下一个版本 |
| 目标标签或 Release 已存在 | 停止发布，确认它是否已经完成；禁止覆盖稳定版本 |
| DMG 校验和或 appcast 验签失败 | 视为发布失败，不手工替换公开资产掩盖问题 |
| `latest` appcast 未指向当前版本 | 等待工作流重试；未收敛前不宣称发布完成 |
| 依赖下载暂时失败 | 先重试；不得为了发布临时修改锁定依赖或候选提交 |

## 禁止事项

- 不在 GitHub 页面手工拼装正式 Release；
- 不为普通发布创建额外预检分支或手动下载 Actions Artifact；
- 不把发布私钥、Keychain 密码或 Authorization 信息写入文件和日志；
- 不使用真实用户剪贴板、SQLite 或 iCloud 同步目录制造发布测试数据；
- 不把“工作流已启动”当作“发布完成”。

## 发布结果记录

完成后记录：

```markdown
## MacTools vX.Y.Z 发布结果

- 候选提交：`<full-sha>`
- 目标分支：`main`
- 版本级别：`patch` / `minor`
- 聚焦测试：通过
- 完整测试：`N/N` 通过
- 条件验证：`<项目和结果；无则写无>`
- Release 工作流：`<run-url>`
- GitHub Release：`<release-url>`
- 公开资产：DMG、SHA-256、appcast 均通过
- Latest appcast：指向当前版本
- 剩余阻断项：无
```
