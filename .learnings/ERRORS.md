# Errors

## [ERR-20260725-005] 凭据字面量启发式误报测试占位值

**Logged**: 2026-07-25T17:03:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tests

### Summary
完成前凭据字面量启发式把现有 SQLite 脱敏测试中的受控占位值识别为可能的真实值。

### Error
```
possible credential literal detected
```

### Context
- 仓库规定需要结合上下文审查关键词扫描结果。
- 唯一命中文件是 `SettingsStoreTests.swift`，其中同时断言该占位值不得进入 SQLite。

### Suggested Fix
先列出命中文件，再人工核对受控测试占位值；启发式只能辅助扫描，不能替代上下文判断。

### Metadata
- Reproducible: yes
- Related Files: `Tests/MacToolsCoreTests/SettingsStoreTests.swift`

### Resolution
- **Resolved**: 2026-07-25T17:03:00+08:00
- **Notes**: 确认两处命中均为同一个显式防泄漏测试占位值，没有真实凭据。

---

## [ERR-20260804-001] image forwarding callback passed the array index as detail

**Logged**: 2026-08-04T15:53:53+08:00
**Priority**: low
**Status**: resolved
**Area**: tooling

### Summary
Forwarding `view_image` results with `Array.forEach(image)` accidentally passed the numeric array index as the
optional image detail argument.

### Error
```
image detail must be a string when provided
```

### Context
- Two local screenshots were loaded in parallel through `view_image`.
- The global `image` helper accepts a second optional detail argument, so `forEach` supplied its index there.
- The failed forwarding call did not modify the screenshots or repository source files.

### Suggested Fix
Forward each result with an explicit single-argument call, such as `for (const item of results) image(item)`.

### Metadata
- Reproducible: yes
- Related Files: .learnings/ERRORS.md

### Resolution
- **Resolved**: 2026-08-04T15:53:53+08:00
- **Notes**: Replaced the callback shorthand with an explicit single-argument forwarding loop.

---

## [ERR-20260804-002] System Events failed while enumerating Chrome windows

**Logged**: 2026-08-04T15:57:34+08:00
**Priority**: low
**Status**: resolved
**Area**: tooling

### Summary
A read-only AppleScript query through System Events failed while collecting Chrome window geometry.

### Error
```
System Events encountered an error: AppleEvent handler failed. (-10000)
```

### Context
- The diagnostic attempted to enumerate Chrome window position, size, subrole, and minimized state without mutating windows.
- The AppleScript bridge failed before returning any window evidence.
- Product behavior and repository files were unaffected.

### Suggested Fix
Use a direct Accessibility API probe instead of routing the query through System Events and AppleScript.

### Metadata
- Reproducible: unknown
- Related Files: Sources/MacTools/Platform/WindowLayout/SystemWindowLayoutService.swift

### Resolution
- **Resolved**: 2026-08-04T15:57:34+08:00
- **Notes**: Discarded the failed AppleScript result and continued with a direct AX API probe.

---

## [ERR-20260804-003] Swift AX probe used an escaped literal inside string interpolation

**Logged**: 2026-08-04T15:58:37+08:00
**Priority**: low
**Status**: resolved
**Area**: tooling

### Summary
A direct Swift Accessibility probe failed to compile because a quoted AX attribute literal was embedded inside a
long string interpolation.

### Error
```
cannot find ')' to match opening '(' in string interpolation
unterminated string literal
```

### Context
- The read-only probe was intended to report Chrome window geometry and whether AX position and size are settable.
- The failure occurred at compile time before any Accessibility query ran.
- The problematic expression interpolated `boolAttribute(window, "AXFullScreen" as CFString)` directly.

### Suggested Fix
Assign all diagnostic attribute names and formatted values to local variables before constructing the output line.

### Metadata
- Reproducible: yes
- Related Files: Sources/MacTools/Platform/WindowLayout/SystemWindowLayoutService.swift
- See Also: ERR-20260725-004

### Resolution
- **Resolved**: 2026-08-04T15:58:37+08:00
- **Notes**: Rewrote the probe to compute each diagnostic value before interpolation.

---

## [ERR-20260728-018] release verification cleanup rejected by command safety policy

**Logged**: 2026-07-28T20:34:30+08:00
**Priority**: low
**Status**: resolved
**Area**: infra

### Summary
The combined GitHub Release verification command was rejected because its exit trap recursively removed a temporary directory.

### Error
```
Rejected: rm -f style commands are not permitted. Use a safer approach
```

### Context
- Attempted to download the published DMG and checksum into a `mktemp -d` directory.
- The command included a scoped `rm -rf` cleanup trap even though the target was the newly created temporary directory.
- The rejection happened before the command started, so no Release asset or local file was changed.

### Suggested Fix
For bounded release verification, create a system temporary directory and leave it for operating-system cleanup instead of including recursive deletion in the command.

### Metadata
- Reproducible: yes
- Related Files: .github/workflows/release.yml

### Resolution
- **Resolved**: 2026-07-28T20:34:30+08:00
- **Notes**: Retried the verification without any deletion command.

---

## [ERR-20260725-004] XCTest 自动闭包不支持 await

**Logged**: 2026-07-25T16:15:22+08:00
**Priority**: medium
**Status**: resolved
**Area**: tests

### Summary
异步协调器测试把 `await` 直接放进 `XCTAssertEqual` 参数，编译器拒绝 actor 调用。

### Error
```
'await' in an autoclosure that does not support concurrency
```

### Context
- `XCTAssertEqual` 的参数是同步自动闭包。
- `CredentialAccessCoordinator.load` 是 actor 隔离方法，调用必须在自动闭包外完成。

### Suggested Fix
先 `await` 取得结果并保存到局部变量，再把普通值传给 XCTest 断言。

### Metadata
- Reproducible: yes
- Related Files: `Tests/MacToolsCoreTests/CredentialAccessCoordinatorTests.swift`

### Resolution
- **Resolved**: 2026-07-25T16:15:22+08:00
- **Notes**: 将异步加载结果移出断言自动闭包；新增 `loadLocal` 测试再次命中后统一采用局部变量模式。

---

## [ERR-20260725-003] Darwin.rename 闭包返回类型不一致

**Logged**: 2026-07-25T16:07:29+08:00
**Priority**: low
**Status**: resolved
**Area**: backend

### Summary
本地凭据原子替换首次编译时，闭包失败分支与 `Darwin.rename` 的返回类型不一致。

### Error
```
cannot convert value of type 'Int32' to closure result type 'Int'
```

### Context
- `guard` 失败分支返回整数字面量 `-1`，Swift 将闭包结果推断为 `Int`。
- `Darwin.rename` 返回 `Int32`，因此同一闭包的两个分支无法统一。

### Suggested Fix
将失败分支显式写为 `Int32(-1)`，保持闭包返回类型与 POSIX API 一致。

### Metadata
- Reproducible: yes
- Related Files: `Sources/MacToolsCore/Settings/EncryptedCredentialStore.swift`

### Resolution
- **Resolved**: 2026-07-25T16:07:29+08:00
- **Notes**: 使用显式 `Int32` 失败值并重新运行聚焦测试。

---

## [ERR-20260725-002] 实施计划样例文件不存在

**Logged**: 2026-07-25T15:57:30+08:00
**Priority**: low
**Status**: resolved
**Area**: docs

### Summary
读取实施计划样例时根据设计文档日期推测了文件名，但仓库中没有对应计划文件。

### Error
```
sed: docs/superpowers/plans/2026-07-20-icloud-drive-sync.md: No such file or directory
```

### Context
- 已先列出 `docs/superpowers/plans`，但读取命令仍使用了未出现在列表中的推测路径。
- 失败只发生在只读查询，没有修改项目或系统状态。

### Suggested Fix
先通过 `rg --files docs/superpowers/plans` 获取真实路径，再选择存在的实施计划作为格式样例。

### Metadata
- Reproducible: yes
- Related Files: `docs/superpowers/plans/`

### Resolution
- **Resolved**: 2026-07-25T15:57:30+08:00
- **Notes**: 改用仓库中实际存在的实施计划文件继续。

---

## [ERR-20260725-001] superpowers 技能缓存版本路径变化

**Logged**: 2026-07-25T15:31:33+08:00
**Priority**: low
**Status**: resolved
**Area**: config

### Summary
读取 `brainstorming` skill 时沿用了上一轮的缓存版本目录，文件已迁移到新版本目录。

### Error
```
sed: .../superpowers/6.1.1/skills/brainstorming/SKILL.md: No such file or directory
```

### Context
- 当前已安装的 superpowers 缓存版本由 `6.1.1` 更新为 `6.2.0`。
- 读取操作失败，没有修改项目或系统状态。

### Suggested Fix
每次新任务从技能目录动态定位 `SKILL.md`，不要复用上一轮缓存版本的绝对路径。

### Metadata
- Reproducible: yes
- Related Files: none

### Resolution
- **Resolved**: 2026-07-25T15:31:33+08:00
- **Notes**: 使用 `rg --files` 定位并完整读取 `6.2.0` 版本的 skill。

---

## [ERR-20260724-003] 设计文档补丁上下文不匹配

**Logged**: 2026-07-24T17:47:32+08:00
**Priority**: low
**Status**: resolved
**Area**: docs

### Summary
更新 ad-hoc Keychain 设计结论时，补丁引用的句子与文件中的实际段落不完全一致。

### Error
```
apply_patch verification failed: Failed to find expected lines
```

### Context
- 尝试一次性修改设计状态、方案结论、验证结论和参考链接。
- 文件未被修改，不影响源代码和运行时状态。

### Suggested Fix
先读取目标文档的实际段落，再拆分为使用精确上下文的最小补丁。

### Metadata
- Reproducible: yes
- Related Files: docs/superpowers/specs/2026-07-24-stable-adhoc-keychain-design.md

### Resolution
- **Resolved**: 2026-07-24T17:47:32+08:00
- **Notes**: 重新读取文档并改用精确段落补丁。

---

## [ERR-20260714-001] ios-macos-development route lookup

**Logged**: 2026-07-14T19:16:00+08:00
**Priority**: low
**Status**: resolved
**Area**: config

### Summary
The macOS debugging route was first read from the skill root instead of its `routes/` directory.

### Error
```
cat: .../ios-macos-development/ios-debugger-agent/guide.md: No such file or directory
```

### Context
- Attempted to read the `ios-debugger-agent` route before rebuilding the SwiftPM macOS app.
- The actual file is `ios-macos-development/routes/ios-debugger-agent/guide.md`.

### Suggested Fix
Resolve route references relative to the skill's `routes/` directory or list skill files before opening a route.

### Metadata
- Reproducible: yes
- Related Files: none

### Resolution
- **Resolved**: 2026-07-14T19:17:00+08:00
- **Notes**: Located and read the route from the correct `routes/ios-debugger-agent/guide.md` path.

---

## [ERR-20260724-002] 带空格技能路径的 sed 命令引号错误

**Logged**: 2026-07-24T17:22:45+08:00
**Priority**: low
**Status**: resolved
**Area**: tests

### Summary
连续读取技能文件时把第二条 `sed` 命令误写入带空格的路径参数，导致文件不存在错误。

### Error
```
sed: .../SKILL.md; sed -n ...: No such file or directory
```

### Context
- 读取 self-improvement 技能文件时，组合命令的引号边界错误。
- 命令仅执行读取，没有修改项目或系统状态。

### Suggested Fix
将带空格的绝对路径先赋给专用变量，再用单条 `sed` 命令读取完整文件。

### Metadata
- Reproducible: yes
- Related Files: none

### Resolution
- **Resolved**: 2026-07-24T17:22:45+08:00
- **Notes**: 改用 `skill_path` 变量并成功读取完整技能文件。

---

## [ERR-20260724-001] 临时证书检查命令触发安全策略

**Logged**: 2026-07-24T17:12:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tests

### Summary
使用带 `rm -f` 清理逻辑的临时证书验证命令被命令安全策略拒绝。

### Error
```
Rejected: rm -f style commands are not permitted. Use a safer approach
```

### Context
- 为排查 Apple Development 证书为何未被代码签名策略识别，尝试用临时 PEM 文件调用 `security verify-cert`。
- 命令在创建进程前被拒绝，没有创建临时文件，也没有修改证书、钥匙串或项目产物。

### Suggested Fix
优先使用不落盘的 `security find-identity`、`security find-certificate` 和 `openssl x509` 只读检查；确需临时文件时使用受控临时目录并避免受限清理形式。

### Metadata
- Reproducible: yes
- Related Files: none

### Resolution
- **Resolved**: 2026-07-24T17:12:00+08:00
- **Notes**: 改用不创建临时文件的证书用途、有效期和身份策略检查。2026-07-29 敏感扫描再次因同类临时文件清理命令被拒绝，随后改为直接流式扫描。

---

## [ERR-20260722-002] 同步周期源代码契约仍读取旧文件

**Logged**: 2026-07-22T18:29:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tests

### Summary
单次同步实现迁移到核心运行器后，源代码契约测试仍读取协调器文件，导致操作次数断言全部为零。

### Error
```
ICloudDriveSyncCoordinatorSourceTests: 3 tests, 7 assertion failures
```

### Context
- 新运行器已经编译成功。
- 失败断言只统计旧文件中的导出、回执和目录扫描调用。

### Suggested Fix
让契约测试读取 `DriveSyncCycleRunner.swift`，并增加执行完整周期的集成测试。

### Metadata
- Reproducible: yes
- Related Files: Tests/MacToolsCoreTests/ICloudDriveSyncCoordinatorSourceTests.swift

### Resolution
- **Resolved**: 2026-07-22T18:29:00+08:00
- **Notes**: 更新契约测试的源文件目标，并以临时存储周期测试补充行为验证。

---

## [ERR-20260722-001] drive-sync-usage-symlink-classification

**Logged**: 2026-07-22T18:04:00+08:00
**Priority**: medium
**Status**: resolved
**Area**: tests

### Summary
临时目录中的同步文字对象被 `usage()` 计入元数据，而 `storedObjects()` 正确识别为文字对象。

### Error
```
XCTAssertEqual failed: ("0") is not equal to ("141")
```

### Context
- 新增存储清单行为锁定测试后稳定复现。
- 测试根目录由系统临时目录生成，路径可能在 `/var` 与 `/private/var` 之间解析。
- 失败位置为 `Tests/MacToolsCoreTests/DriveSyncStoreTests.swift` 的文字对象字节分类断言。

### Suggested Fix
确认枚举 URL 与预先构造对象目录的规范路径是否一致；统一存储清单应按相对路径组件分类，避免依赖字符串绝对路径前缀。

### Metadata
- Reproducible: yes
- Related Files: Sources/MacToolsCore/Sync/DriveSyncStore.swift, Tests/MacToolsCoreTests/DriveSyncStoreTests.swift

### Resolution
- **Resolved**: 2026-07-22T18:06:19+08:00
- **Notes**: 已改为按同步协议相对结构 `objects/{text|images}/sha256` 分类，不再比较可能分别为 `/var` 与 `/private/var` 的绝对路径；聚焦回归测试通过。

---

## [ERR-20260714-003] liquid glass offscreen snapshot rendering

**Logged**: 2026-07-14T19:45:00+08:00
**Priority**: medium
**Status**: pending
**Area**: tests

### Summary
SwiftUI `ImageRenderer` produced correctly sized but visually black images for Liquid Glass panels.

### Error
```
Generated PNG files contain no inspectable panel content even though rendering and pixel-size assertions pass.
```

### Context
- Rendered `ContextActionView` with macOS 26 `glassEffect` outside a live AppKit window.
- The effect depends on live window/backdrop composition and is not represented by the offscreen renderer.

### Suggested Fix
Use a launched packaged app and real `NSPanel` screenshots for Liquid Glass visual verification; keep offscreen snapshots only for size/smoke assertions unless a deterministic backdrop renderer is introduced.

### Metadata
- Reproducible: yes
- Related Files: Tests/MacToolsCoreTests/SuperPanelSnapshotTests.swift

---

## [ERR-20260714-002] super panel snapshot pixel assertion

**Logged**: 2026-07-14T19:44:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tests

### Summary
Fractional point sizes render by rounding pixel dimensions up, while the snapshot assertion truncated them.

### Error
```
XCTAssertEqual failed: ("827") is not equal to ("826")
XCTAssertEqual failed: ("590") is not equal to ("589")
```

### Context
- Generated a 2x snapshot after increasing the translation panel to a fractional `4 / 3` scale.
- `ImageRenderer` produced the required enclosing pixel dimensions, but `Int(...)` truncated the expected value.

### Suggested Fix
Round expected rendered pixel dimensions upward before converting them to integers.

### Metadata
- Reproducible: yes
- Related Files: Tests/MacToolsCoreTests/SuperPanelSnapshotTests.swift

### Resolution
- **Resolved**: 2026-07-14T19:44:00+08:00
- **Notes**: Updated both pixel assertions to use `rounded(.up)`.

---

## [ERR-20260715-001] GitHub Release CLI unavailable

**Logged**: 2026-07-15T19:00:06+08:00
**Priority**: medium
**Status**: resolved
**Area**: infra

### Summary
The local environment does not have the GitHub CLI installed for creating a release.

### Error
```
zsh: command not found: gh
```

### Context
- Attempted to inspect authentication, repository metadata, and existing releases before publishing a DMG.
- The checkout has a GitHub `origin`, but the expected `gh` executable is absent from `PATH`.

### Suggested Fix
Use the connected GitHub integration when it exposes release operations, install GitHub CLI, or call the GitHub REST API with an existing credential without printing or persisting the token.

### Metadata
- Reproducible: yes
- Related Files: scripts/package_app.sh

### Resolution
- **Resolved**: 2026-07-15T19:25:00+08:00
- **Notes**: Added a tag-triggered GitHub Actions release workflow that uses the runner-provided authenticated GitHub CLI.

---

## [ERR-20260715-002] DMG overwrite while prior image is attached

**Logged**: 2026-07-15T19:12:00+08:00
**Priority**: medium
**Status**: resolved
**Area**: infra

### Summary
Overwriting a DMG path that still had an attached disk image made immediate verification fail with a temporary resource error.

### Error
```
hdiutil: verify: unable to recognize "dist/MacTools-v0.1.0-arm64-macos26.dmg" as a disk image. (资源暂时不可用)
```

### Context
- Repeated the local release check after mounting the previously generated DMG.
- `hdiutil info` showed the target image still attached and `lsof` showed `diskimages-helper` holding the path.
- Detaching the stale device made the same DMG verify successfully.

### Suggested Fix
Create the replacement DMG at a unique temporary path and atomically move it into place; detach test mounts by their device identifier instead of suppressing mountpoint-detach failures.

### Metadata
- Reproducible: yes
- Related Files: scripts/create_dmg.sh, .github/workflows/release.yml

### Resolution
- **Resolved**: 2026-07-15T19:14:00+08:00
- **Notes**: DMG creation now uses a temporary output path before replacement, and CI captures the attached device for cleanup.

---

## [ERR-20260715-003] Final release verification shell quoting

**Logged**: 2026-07-15T19:17:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tests

### Summary
A composite zsh verification command had an unmatched quote around the mounted bundle version lookup.

### Error
```
zsh: unmatched "
```

### Context
- The failure occurred while assembling the verification command, before tests, packaging, or launch ran.
- The nested command substitution mixed the mount path quoting with the surrounding comparison.

### Suggested Fix
Capture PlistBuddy output in a named variable before comparing it.

### Metadata
- Reproducible: yes
- Related Files: none

### Resolution
- **Resolved**: 2026-07-15T19:18:00+08:00
- **Notes**: Replaced the nested comparison with a mounted-version variable in the verification command.

---

## [ERR-20260715-004] Anonymous GitHub Actions status rate limit

**Logged**: 2026-07-15T19:20:00+08:00
**Priority**: low
**Status**: resolved
**Area**: infra

### Summary
The unauthenticated GitHub REST fallback could not query the tag-triggered workflow because the shared egress IP exhausted its anonymous core API quota.

### Error
```
HTTP/2 403
x-ratelimit-remaining: 0
```

### Context
- Queried public workflow runs after pushing `v0.1.0` because the local environment has no GitHub CLI.
- GitHub returned an anonymous limit of 60 requests with zero remaining.
- The authenticated GitHub connector also timed out on its first workflow-job lookup, so monitoring fell back to the public Actions HTML page.

### Suggested Fix
Use the authenticated GitHub connector, GitHub web status, or a locally authenticated CLI instead of anonymous REST for release monitoring.

### Metadata
- Reproducible: yes
- Related Files: .github/workflows/release.yml

### Resolution
- **Resolved**: 2026-07-15T19:25:00+08:00
- **Notes**: Monitored the run through the authenticated connector after the transient timeout, then downloaded and verified both public Release assets directly.

---

## [ERR-20260716-001] Spotlight UI automation denied

**Logged**: 2026-07-16T11:09:05+08:00
**Priority**: low
**Status**: resolved
**Area**: tests

### Summary
The shell could not open and type into Spotlight for an automated visual check because macOS denied synthetic keyboard events.

### Error
```
“osascript”不允许发送按键。 (1002)
```

### Context
- Attempted to reproduce the reported Spotlight icon result after rebuilding and registering `build/MacTools.app`.
- The current terminal process does not have the Accessibility permission required by System Events to send keyboard input.

### Suggested Fix
Keep the Finder and Spotlight check in the manual verification checklist. For automated evidence, render the packaged application icon through `NSWorkspace` without requesting additional system permissions.

### Metadata
- Reproducible: yes
- Related Files: docs/manual-verification.md, scripts/package_app.sh

### Resolution
- **Resolved**: 2026-07-16T11:09:05+08:00
- **Notes**: Verified the packaged and DMG-contained app with `NSWorkspace`, and added the direct Finder/Spotlight check to the manual checklist.

---

## [ERR-20260727-001] Swift method signature mismatch after API split

**Logged**: 2026-07-27T11:39:14+08:00
**Priority**: low
**Status**: resolved
**Area**: tests

### Summary
Splitting editor presentation into prepare and present phases left the old `Bool` return type on the new preparation method.

### Error
```
missing return in instance method expected to return 'Bool'
```

### Context
- Ran the focused screen-capture test suite after splitting `present` into `prepare` and `presentPrepared`.
- The method body had been converted to a side-effect-only preparation phase, but its declaration still returned `Bool`.

### Suggested Fix
When splitting a method, review its declaration, all call sites, and the compiler warning for unused results together before rerunning tests.

### Metadata
- Reproducible: yes
- Related Files: Sources/MacTools/App/ScreenCapture/ScreenshotEditorPanelController.swift

### Resolution
- **Resolved**: 2026-07-27T11:39:14+08:00
- **Notes**: Removed the stale return type and reran the focused suite successfully.

---

## [ERR-20260727-003] Generated CodeGraph directory removal rejected

**Logged**: 2026-07-27T14:40:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tooling

### Summary
The command guard rejected recursive removal of the generated repository-local CodeGraph index.

### Error
```
rm -f style commands are not permitted. Use a safer approach
```

### Context
- The `.codegraph` directory was generated during the current review and was not user-owned source.
- The command used an explicit validated path, but the environment still blocks recursive forced removal.

### Suggested Fix
Move generated review artifacts out of the workspace to a unique temporary path instead of removing them recursively.

### Metadata
- Reproducible: yes
- Related Files: .codegraph/

### Resolution
- **Resolved**: 2026-07-27T14:40:00+08:00
- **Notes**: Moved the generated index to a task-specific path under `/tmp`.

---

## [ERR-20260727-002] CodeGraph edge schema field mismatch

**Logged**: 2026-07-27T14:28:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tests

### Summary
The first CodeGraph edge statistics query used `type`, while the local index schema names the relation column `kind`.

### Error
```
no such column: type
```

### Context
- Initialized the repository CodeGraph index to review unused Swift symbols.
- Inspected the `edges` table schema but reused a generic graph field name in the following aggregation query.

### Suggested Fix
Query `pragma_table_info` or the emitted `.schema` result before composing ad hoc CodeGraph SQL.

### Metadata
- Reproducible: yes
- Related Files: .codegraph/codegraph.db

### Resolution
- **Resolved**: 2026-07-27T14:28:00+08:00
- **Notes**: Updated the read-only aggregation to group by `edges.kind`.

---

## [ERR-20260727-004] Sensitive-word scan treated expected identifiers as credentials

**Logged**: 2026-07-27T14:57:43+08:00
**Priority**: low
**Status**: resolved
**Area**: tooling

### Summary
The pre-push merge-diff scan failed because broad sensitive-word matching treated expected identifiers such as `credential` and `session` as credential literals.

### Error
```
translationCredentialUnavailable
testRuntimeRetainsSelectionForCurrentAppSessionAndDefaultsToGeneral
```

### Context
- Scanned the complete diff, including unchanged context lines, with a broad credential-related regular expression.
- The matches were legitimate Swift identifiers and did not contain credential values.
- The failed command stopped before `git push origin main`, so no remote state was changed.

### Suggested Fix
Limit the automated scan to added lines, retain the repository exclusions, and review each match in context instead of treating every sensitive field name as a secret.

### Metadata
- Reproducible: yes
- Related Files: Sources/MacTools/App/RuntimeViews.swift, Tests/MacToolsCoreTests/SettingsNavigationTests.swift

### Resolution
- **Resolved**: 2026-07-27T14:57:43+08:00
- **Notes**: Replaced the blocking broad match with an added-line scan and contextual review.

---

## [ERR-20260727-005] macOS app launch used a relative path

**Logged**: 2026-07-27T15:10:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tooling

### Summary
The UI verification launch command passed a relative app path to `open -a`, which was interpreted as an application name.

### Error
```
Unable to find application named 'build/MacTools.app'
```

### Context
- Attempted to relaunch the packaged app with the UI verification argument.
- `open -a` resolves an application name, not a repository-relative bundle path.
- The package build and signing step had already succeeded.

### Suggested Fix
Pass the absolute bundle path directly to `open -na`, without `-a`.

### Metadata
- Reproducible: yes
- Related Files: scripts/rebuild_and_run_app.sh

### Resolution
- **Resolved**: 2026-07-27T15:10:00+08:00
- **Notes**: Corrected the verification launch command to use the absolute app bundle path.

---

## [ERR-20260727-006] System Events UI inspection lacked accessibility permission

**Logged**: 2026-07-27T15:11:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tooling

### Summary
System Events could not inspect or drive the packaged MacTools window because the current `osascript` process lacks Accessibility permission.

### Error
```
“osascript”不允许辅助访问。
```

### Context
- Attempted to inspect the packaged app's UI hierarchy and click the reported controls.
- The app launched successfully and its window was available through Core Graphics window metadata.

### Suggested Fix
Use deterministic SwiftUI regression tests and packaged-app screenshots in restricted environments; reserve System Events control for a terminal process with Accessibility permission.

### Metadata
- Reproducible: yes
- Related Files: Sources/MacToolsCore/UI/SettingsNavigation.swift

### Resolution
- **Resolved**: 2026-07-27T15:11:00+08:00
- **Notes**: Continued with source tracing, focused tests, and packaged-app visual verification.

---

## [ERR-20260727-007] Python Quartz bridge was unavailable

**Logged**: 2026-07-27T15:12:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tooling

### Summary
The default Python runtime does not include the PyObjC Quartz module needed for Core Graphics event inspection.

### Error
```
ModuleNotFoundError: No module named 'Quartz'
```

### Context
- Checked whether the existing Python runtime could inspect the pointer position without installing dependencies.

### Suggested Fix
Use the system Swift toolchain for read-only Core Graphics inspection instead of assuming PyObjC is installed.

### Metadata
- Reproducible: yes
- Related Files: Package.swift

### Resolution
- **Resolved**: 2026-07-27T15:12:00+08:00
- **Notes**: Replaced the Python probe with a Swift/CoreGraphics probe.

---

## [ERR-20260727-008] Liquid Glass regression assertion was broader than the invariant

**Logged**: 2026-07-27T15:17:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tests

### Summary
The first green-phase regression assertion rejected every conditional surface decision instead of only rejecting replacement of the button hit target.

### Error
```
XCTAssertFalse failed
```

### Context
- Initially suspected that the button style replaced its hit target while pressed.
- A real AppKit click test subsequently proved that the existing Liquid Glass button style still completes the action.
- The actual runtime comparison isolated the explicit settings-navigation animation instead.

### Suggested Fix
Validate the suspected interaction with an AppKit click before changing a shared button style.

### Metadata
- Reproducible: yes
- Related Files: Tests/MacToolsCoreTests/LiquidGlassSurfaceTests.swift

### Resolution
- **Resolved**: 2026-07-27T15:45:00+08:00
- **Notes**: Removed the speculative Liquid Glass implementation and test changes; kept the shared style unchanged.

---

## [ERR-20260727-009] Core Graphics event probe used obsolete Swift signatures

**Logged**: 2026-07-27T15:33:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tooling

### Summary
A temporary Swift event probe used an outdated `CGEventPostToPid` signature and an invalid dictionary cast.

### Error
```
cannot find 'CGEventPostToPid' in scope
cannot convert value of type 'CFDictionary' to type '[String : Any]'
```

### Context
- Attempted to send a process-targeted mouse click and inspect the MacTools window.
- The current SDK exposes process posting through `CGEvent.postToPid(_:)`.

### Suggested Fix
Use the current SDK method and cast window metadata from the array returned by `CGWindowListCopyWindowInfo`.

### Metadata
- Reproducible: yes
- Related Files: Sources/MacToolsCore/UI/SettingsNavigation.swift

### Resolution
- **Resolved**: 2026-07-27T15:34:00+08:00
- **Notes**: Replaced the obsolete probe and moved the decisive verification into the app process.

---

## [ERR-20260727-010] Window lookup probe terminated with fatalError

**Logged**: 2026-07-27T15:36:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tooling

### Summary
A temporary window-inspection probe used `fatalError` when the MacTools window was not present at that instant.

### Error
```
Fatal error: MacTools window not found
```

### Context
- The settings panel hides when the accessory app deactivates.
- Window absence is expected during that transition and should not crash a diagnostic.

### Suggested Fix
Return a normal nonzero result or print an empty-state message for timing-sensitive window probes.

### Metadata
- Reproducible: yes
- Related Files: Sources/MacTools/App/MainPanelController.swift

### Resolution
- **Resolved**: 2026-07-27T15:37:00+08:00
- **Notes**: Subsequent probes handled missing windows without trapping.

---

## [ERR-20260727-011] Native control click test blocked in mouse tracking

**Logged**: 2026-07-27T15:38:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tests

### Summary
A direct `mouseDown` call against the appearance picker blocked while the native control waited for `mouseUp`.

### Error
```
Focused test did not complete until interrupted.
```

### Context
- Native segmented controls run a tracking loop during `mouseDown`.
- Sending `mouseUp` only after `mouseDown` returns cannot complete that loop.

### Suggested Fix
Queue the matching `mouseUp` on `NSApp` before delivering `mouseDown`.

### Metadata
- Reproducible: yes
- Related Files: Tests/MacToolsCoreTests/SettingsNavigationTests.swift

### Resolution
- **Resolved**: 2026-07-27T15:39:00+08:00
- **Notes**: Used an event-queue-aware click during diagnosis and removed the exploratory picker test afterward.

---

## [ERR-20260727-012] Obsolete Core Graphics window capture API was unavailable

**Logged**: 2026-07-27T16:02:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tooling

### Summary
The current macOS SDK rejects `CGWindowListCreateImage`, which was obsoleted in macOS 15.

### Error
```
'CGWindowListCreateImage' is unavailable in macOS: Please use ScreenCaptureKit instead.
```

### Context
- Attempted to capture a temporarily hidden settings panel for an old/new behavior comparison.

### Suggested Fix
Use `screencapture -l` for an available window or ScreenCaptureKit for programmatic capture.

### Metadata
- Reproducible: yes
- Related Files: Sources/MacTools/App/ScreenCapture

### Resolution
- **Resolved**: 2026-07-27T16:06:00+08:00
- **Notes**: Captured the target window by ID after ordering it for verification.

---

## [ERR-20260727-013] 敏感信息附加正则的 shell 引号不匹配

**Logged**: 2026-07-27T21:53:30+08:00
**Priority**: low
**Status**: resolved
**Area**: tooling

### Summary
将含单双引号的高置信凭据正则内嵌到一条 zsh 命令时产生未闭合引号。

### Error
```
zsh:1: unmatched "
```

### Context
- 基础格式检查、签名检查和进程检查已独立执行成功。
- 失败发生在附加敏感信息扫描的命令解析阶段，没有读取运行时数据或修改项目状态。

### Suggested Fix
将复杂正则拆成不包含嵌套引号的多个 `rg -e` 参数，或使用工具参数传递而不是拼接 shell 字符串。

### Metadata
- Reproducible: yes
- Related Files: none
- See Also: ERR-20260715-003

### Resolution
- **Resolved**: 2026-07-27T21:53:30+08:00
- **Notes**: 改用不含嵌套引号的分项正则重新执行扫描。

---
## [ERR-20260728-004] imprecise learning status patch

**Logged**: 2026-07-28T13:04:00+08:00
**Priority**: low
**Status**: resolved
**Area**: docs

### Summary
A generic status replacement updated an unrelated historical learning entry.

### Error
```
ERR-20260714-003 changed from pending to resolved
```

### Context
- Attempted to resolve the newly added SwiftUI interface lookup entry using a hunk that matched the first `Status: pending` line in the file.
- Diff review caught the unrelated change before staging or committing.

### Suggested Fix
Always anchor learning-status updates with the exact entry heading and logged timestamp.

### Metadata
- Reproducible: yes
- Related Files: .learnings/ERRORS.md

### Resolution
- **Resolved**: 2026-07-28T13:04:00+08:00
- **Notes**: Restored the historical entry to pending and updated only ERR-20260728-002.

---

## [ERR-20260728-003] multi-file interaction fix patch

**Logged**: 2026-07-28T12:58:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tests

### Summary
A combined source-and-test patch did not match the exact button modifier context.

### Error
```
apply_patch verification failed: Failed to find expected lines in
Sources/MacToolsCore/UI/LiquidGlassSurface.swift
```

### Context
- Attempted to add the identity glass style, update the button modifier, and adjust two test files in one patch.
- The modifier replacement hunk contained mismatched closing-line context, so the patch was rejected atomically.

### Suggested Fix
Inspect the exact line-numbered source and apply smaller independently verifiable hunks.

### Metadata
- Reproducible: yes
- Related Files: Sources/MacToolsCore/UI/LiquidGlassSurface.swift, Tests/MacToolsCoreTests/SettingsNavigationTests.swift

### Resolution
- **Resolved**: 2026-07-28T12:59:00+08:00
- **Notes**: Re-read the exact source context and split the change into focused patches.

---

## [ERR-20260728-002] SwiftUI glass API interface lookup

**Logged**: 2026-07-28T11:46:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tests

### Summary
The local SwiftUI API lookup passed an empty interface path to ripgrep.

### Error
```
rg: : IO error for operation on : No such file or directory (os error 2)
```

### Context
- Queried the active macOS SDK for an `*apple-macos.swiftinterface` path under `SwiftUI.framework`.
- The selected SDK does not expose the module interface at that globbed location, so `find` returned no result.

### Suggested Fix
Locate the active toolchain module interface first, validate that the path is non-empty, and only then search it.

### Metadata
- Reproducible: yes
- Related Files: Sources/MacToolsCore/UI/LiquidGlassSurface.swift

### Resolution
- **Resolved**: 2026-07-28T12:50:00+08:00
- **Notes**: Located the interface under `SwiftUI.framework/Versions/A/Modules` and confirmed that `Glass.identity` is available on macOS 26.

---

## [ERR-20260728-001] packaged settings navigation probe

**Logged**: 2026-07-28T11:42:00+08:00
**Priority**: low
**Status**: pending
**Area**: tests

### Summary
The packaged-app navigation probe could not capture the settings panel and its temporary Swift event sender did not compile.

### Error
```
window_id=
could not create image from window
conditional downcast to CoreFoundation type 'CFDictionary' will always succeed
```

### Context
- Relaunched the packaged app with `--ui-verification-open-settings`, then queried only on-screen Core Graphics windows from a later shell process.
- The transient settings panel was already no longer on screen when the query ran.
- The event sender conditionally cast the window-bounds dictionary to `CFDictionary`, which Swift 6 diagnoses as an error.
- A second capture immediately after the post-fix packaged launch still found only the hidden panel, so external screenshot automation cannot validate this transient window in the current session.

### Suggested Fix
Keep launch, window lookup, interaction, and capture in one foreground-safe probe, and bridge the bounds dictionary directly with `as CFDictionary`.

### Metadata
- Reproducible: yes
- Related Files: Sources/MacToolsCore/Panels/MainPanelController.swift, Tests/MacToolsCoreTests/SettingsNavigationTests.swift
- See Also: ERR-20260727-006, ERR-20260727-009, ERR-20260727-010

---

## [ERR-20260728-005] SwiftUI style scan regex

**Logged**: 2026-07-28T17:36:31+08:00
**Priority**: low
**Status**: resolved
**Area**: frontend

### Summary
A combined ripgrep expression for SwiftUI style usage contained an unbalanced nested group.

### Error
```
rg: regex parse error:
error: unopened group
```

### Context
- Attempted to scan several SwiftUI styling calls and frame labels in one large regular expression.
- The nested `frame` alternative introduced an extra closing parenthesis.

### Suggested Fix
Use multiple simple `-e` expressions for independent SwiftUI style patterns instead of one deeply nested expression.

### Metadata
- Reproducible: yes
- Related Files: Sources/MacToolsCore/UI, Sources/MacTools/App/RuntimeViews.swift
- See Also: ERR-20260727-010

### Resolution
- **Resolved**: 2026-07-28T17:36:31+08:00
- **Notes**: Replaced the combined expression with separate fixed-string and simple regular-expression searches.

---

## [ERR-20260728-006] visual companion startup permission

**Logged**: 2026-07-28T17:39:07+08:00
**Priority**: low
**Status**: resolved
**Area**: infra

### Summary
The bundled visual companion startup script is readable but not executable.

### Error
```
zsh: permission denied: .../brainstorming/scripts/start-server.sh
```

### Context
- Invoked the bundled `start-server.sh` directly after the user enabled the visual companion.
- The cached plugin file mode is `-rw-r--r--`.

### Suggested Fix
Invoke the readable script explicitly with `bash` instead of changing permissions in the plugin cache.

### Metadata
- Reproducible: yes
- Related Files: none

### Resolution
- **Resolved**: 2026-07-28T17:39:07+08:00
- **Notes**: Switched the launch command to `bash start-server.sh`.

---

## [ERR-20260728-007] CodeGraph unavailable for UI implementation

**Logged**: 2026-07-28T19:37:36+08:00
**Priority**: low
**Status**: resolved
**Area**: frontend

### Summary
The repository-local CodeGraph index is not initialized for the unified UI implementation.

### Error
```
CodeGraph not initialized in /Users/bytedance/code/mytools
```

### Context
- Attempted to survey the confirmed UI symbols before editing.
- A previous review generated and then removed the repository-local index, so the connected query cannot operate.

### Suggested Fix
Use the already inspected Swift sources and focused `rg` queries for this bounded change; initialize CodeGraph only when a future task requires a fresh broad dependency index.

### Metadata
- Reproducible: yes
- Related Files: Sources/MacToolsCore/UI, Sources/MacTools/App/ScreenCapture
- See Also: ERR-20260727-003

### Resolution
- **Resolved**: 2026-07-28T19:37:36+08:00
- **Notes**: Continued with the previously audited source set and focused local checks without generating a new repository index.

---

## [ERR-20260728-008] translation workspace combined patch

**Logged**: 2026-07-28T19:40:04+08:00
**Priority**: low
**Status**: resolved
**Area**: frontend

### Summary
A combined translation workspace patch did not match the complete current source context.

### Error
```
apply_patch verification failed: Failed to find expected lines in
Sources/MacTools/App/RuntimeViews.swift
```

### Context
- Attempted to flatten the translation page and update its source-contract test in one patch.
- One multi-line modifier hunk was rejected atomically even though the surrounding view remained unchanged.

### Suggested Fix
Read the exact translation view range and apply smaller body, input, output, and test hunks independently.

### Metadata
- Reproducible: yes
- Related Files: Sources/MacTools/App/RuntimeViews.swift, Tests/MacToolsCoreTests/TranslationModuleSourceTests.swift
- See Also: ERR-20260728-003

### Resolution
- **Resolved**: 2026-07-28T19:40:04+08:00
- **Notes**: Re-read the exact source and split the edit into focused patches.

---

## [ERR-20260728-009] unavailable SwiftUI button style eraser

**Logged**: 2026-07-28T19:42:32+08:00
**Priority**: low
**Status**: resolved
**Area**: frontend

### Summary
A conditional SwiftUI button-style implementation referenced a nonexistent `AnyButtonStyle` type.

### Error
```
cannot find type 'AnyButtonStyle' in scope
```

### Context
- Attempted to return either the primary or secondary translation button style from one computed property.
- SwiftUI does not provide the assumed public button-style type eraser in this toolchain.

### Suggested Fix
Branch at the view-builder level and apply each concrete `ButtonStyle` to the shared button view.

### Metadata
- Reproducible: yes
- Related Files: Sources/MacToolsCore/UI/ContextActionView.swift

### Resolution
- **Resolved**: 2026-07-28T19:42:32+08:00
- **Notes**: Replaced style type erasure with an `@ViewBuilder` branch over a shared action button.

---

## [ERR-20260728-010] compact editor toolbar changes narrow-screen placement

**Logged**: 2026-07-28T19:44:24+08:00
**Priority**: low
**Status**: resolved
**Area**: testing

### Summary
The narrow-display layout expectation still assumed the former two-row editor toolbar height.

### Error
```
XCTAssertEqual failed: ("(12.0, 20.0, 476.0, 68.0)") is not equal to ("(12.0, 352.0, 476.0, 68.0)")
```

### Context
- The toolbar height changed from 92 to 68 points.
- At the smaller height the toolbar now fits below the sample selection, so the layout correctly follows its below-selection preference.

### Suggested Fix
Update the test expectation to the new below-selection frame while keeping the existing placement policy unchanged.

### Metadata
- Reproducible: yes
- Related Files: Sources/MacToolsCore/ScreenCapture/ScreenCaptureOverlayLayout.swift, Tests/MacToolsCoreTests/ScreenCaptureOverlayLayoutTests.swift

### Resolution
- **Resolved**: 2026-07-28T19:44:24+08:00
- **Notes**: Corrected the expected narrow-display frame to `(12, 20, 476, 68)`.

---

## [ERR-20260728-011] AppleScript key injection denied during UI verification

**Logged**: 2026-07-28T20:02:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tooling

### Summary
AppleScript could not send the configured keyboard shortcut while verifying the packaged app.

### Error
```
System Events got an error: “osascript” is not allowed to send keystrokes. (1002)
```

### Context
- Attempted to open the packaged app's panels through their global keyboard shortcuts.
- The shell process does not have Accessibility permission for synthetic key events.

### Suggested Fix
Use the existing packaged-app UI verification launch argument and activate the app by bundle path instead of requesting broader system permission.

### Metadata
- Reproducible: yes
- Related Files: Sources/MacTools/App/AppDelegate.swift, scripts/rebuild_and_run_app.sh

### Resolution
- **Resolved**: 2026-07-28T20:02:00+08:00
- **Notes**: Switched to the app's UI verification launch path and did not change TCC permissions.

---

## [ERR-20260728-012] on-screen-only window lookup missed an ordered-out panel

**Logged**: 2026-07-28T20:08:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tooling

### Summary
A diagnostic Swift helper failed to find the verification panel after the panel lost key-window status.

### Error
```
Fatal error: MacTools window not found
```

### Context
- The helper queried only on-screen windows after launching the packaged app.
- The panel had already been ordered out, but its rounded AppKit window remained available in the complete Core Graphics window list.

### Suggested Fix
Resolve the window by the packaged app process ID with the complete window list, then capture the known panel window directly.

### Metadata
- Reproducible: yes
- Related Files: Sources/MacToolsCore/Panels/MainPanelController.swift

### Resolution
- **Resolved**: 2026-07-28T20:08:00+08:00
- **Notes**: Located the layer-zero panel in the complete window list and completed the visual inspection.

---

## [ERR-20260728-013] full test process crashed while capture verification session was active

**Logged**: 2026-07-28T20:06:00+08:00
**Priority**: medium
**Status**: resolved
**Area**: testing

### Summary
The full XCTest process exited with signal 11 while the packaged app still owned an active screen-capture overlay.

### Error
```
Process 'xctest …/MacToolsPackageTests.xctest' exited with unexpected signal code 11
```

### Context
- The packaged MacTools app was intentionally left in screenshot-editing verification state.
- All reported assertions had passed before the test process terminated near the translation suites.
- The translation suite passed in isolation after the packaged app was stopped.

### Suggested Fix
End packaged UI verification sessions before running the in-process XCTest suite so AppKit and capture resources are not shared concurrently.

### Metadata
- Reproducible: no
- Related Files: Sources/MacTools/App/ScreenCapture, Tests/MacToolsCoreTests

### Resolution
- **Resolved**: 2026-07-28T20:06:06+08:00
- **Notes**: Stopped the packaged capture session; the isolated translation suite passed 7 tests and the full suite then passed 445 tests.

---

## [ERR-20260728-014] CodeGraph unavailable for button hit-area investigation

**Logged**: 2026-07-28T20:24:00+08:00
**Priority**: medium
**Status**: resolved
**Area**: frontend

### Summary
The repository-local CodeGraph index is still unavailable while investigating SwiftUI button hit testing.

### Error
```
CodeGraph not initialized in /Users/bytedance/code/mytools
```

### Context
- Attempted to trace `ScreenshotEditorView`, shared Liquid Glass button styles, and related callers before editing.
- The repository does not currently contain an initialized `.codegraph` index.

### Suggested Fix
Use focused source and test searches for this bounded regression; initialize CodeGraph separately only when a future broad dependency investigation justifies modifying repository tooling state.

### Metadata
- Reproducible: yes
- Related Files: Sources/MacToolsCore/UI/LiquidGlassSurface.swift, Sources/MacTools/App/ScreenCapture/ScreenshotEditorView.swift
- See Also: ERR-20260728-007

### Resolution
- **Resolved**: 2026-07-28T20:24:00+08:00
- **Notes**: Continued with exact source ranges, recent diff inspection, and focused tests without creating a new repository index.
- **Recurrence**: 2026-07-30; a broad performance audit also could not use CodeGraph. Continued with repository-wide `rg`, direct source inspection, and runtime sampling.

---

## [ERR-20260728-015] hit-area source test expected member-call punctuation

**Logged**: 2026-07-28T20:17:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tests

### Summary
The new source-contract test expected `.contentShape` even though the helper uses an implicit `self` call spelled `contentShape`.

### Error
```
XCTAssertTrue failed at ScreenshotPresentationSourceTests.swift:138
```

### Context
- The implementation compiled successfully and all other new source assertions passed.
- Inspecting the exact helper body showed the test's leading punctuation was the only mismatch.

### Suggested Fix
Match the stable method call and interaction shape arguments without depending on optional member-call punctuation.

### Metadata
- Reproducible: yes
- Related Files: Tests/MacToolsCoreTests/ScreenshotPresentationSourceTests.swift, Sources/MacToolsCore/UI/LiquidGlassSurface.swift

### Resolution
- **Resolved**: 2026-07-28T20:17:00+08:00
- **Notes**: Corrected the source assertion to match `contentShape(` while retaining the `.interaction` contract.

---

## [ERR-20260728-016] consecutive AppKit click tests crashed in window animation cleanup

**Logged**: 2026-07-28T20:20:00+08:00
**Priority**: medium
**Status**: pending
**Area**: tests

### Summary
Running the new hit-target window test immediately before the existing settings-toolbar click test crashed AppKit while releasing a window transform animation.

### Error
```
EXC_BAD_ACCESS in -[_NSWindowTransformAnimation dealloc]
```

### Context
- Both tests passed independently.
- The two-test sequence consistently crashed when the second test advanced the main run loop.
- The crash report placed the fault in AppKit animation cleanup, not application code or a test assertion.
- On 2026-07-29, a full-suite verification run reproduced the same `EXC_BAD_ACCESS` in `-[_NSWindowTransformAnimation dealloc]` after a previous full-suite pass and green credential-focused tests.

### Suggested Fix
Keep the real edge click on the repository's existing settings control instead of introducing another SwiftUI button or NSWindow into the same XCTest lifecycle.

### Metadata
- Reproducible: yes
- Related Files: Tests/MacToolsCoreTests/LiquidGlassSurfaceTests.swift, Tests/MacToolsCoreTests/SettingsNavigationTests.swift

### Resolution
- **Resolved**: 2026-07-28T20:20:00+08:00
- **Notes**: Removed the extra SwiftUI button and second NSWindow test, then added the edge click to the existing stable settings-category control; plain glass callers remain covered by the failing-then-passing source contract.
- **Recurrence**: 2026-07-29T14:56:58+08:00; two single-process full-suite runs reproduced the AppKit crash several seconds after the window click test.
- **Workaround verified**: 2026-07-29T15:01:10+08:00; the 449 remaining tests passed together, and the isolated window click test passed separately. Keep the issue pending until the real-window test no longer leaves AppKit transform-animation cleanup behind.

---

## [ERR-20260728-017] multi-file patch omitted the second file marker

**Logged**: 2026-07-28T20:23:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tests

### Summary
A combined cleanup patch tried to match the learning-entry context in the test file because the second update-file marker was omitted.

### Error
```
apply_patch verification failed: Failed to find expected lines in SettingsNavigationTests.swift
```

### Context
- The intended patch updated both the AppKit test harness and its error record.
- The patch was rejected atomically, so no partial source change occurred.

### Suggested Fix
Declare each file explicitly in a multi-file patch and keep unrelated hunks under their own update marker.

### Metadata
- Reproducible: yes
- Related Files: Tests/MacToolsCoreTests/SettingsNavigationTests.swift, .learnings/ERRORS.md

### Resolution
- **Resolved**: 2026-07-28T20:23:00+08:00
- **Notes**: Reapplied the two updates with explicit file markers.

---

## [ERR-20260729-001] Swift window probe escaped dictionary keys inside interpolation

**Logged**: 2026-07-29T14:39:00+08:00
**Priority**: low
**Status**: resolved
**Area**: infra

### Summary
A temporary `swift -e` window-inspection probe failed because escaped dictionary-key literals were embedded directly inside string interpolation.

### Error
```
error: cannot find ')' to match opening '(' in string interpolation
error: unterminated string literal
```

### Context
- The probe only read CoreGraphics window metadata and did not modify the application or repository.
- Shell quoting added unnecessary escapes around `bounds["Width"]` and `bounds["Height"]` inside the Swift interpolation.

### Suggested Fix
Assign dictionary values to local variables before interpolating them into diagnostic output.

### Metadata
- Reproducible: yes
- Related Files: .learnings/ERRORS.md
- See Also: ERR-20260725-004

### Resolution
- **Resolved**: 2026-07-29T14:39:00+08:00
- **Notes**: Moved the width and height lookups into local variables; the corrected probe reported zero on-screen MacTools windows.

---

## [ERR-20260729-002] apply_patch rejected content-free file moves

**Logged**: 2026-07-29T16:00:00+08:00
**Priority**: low
**Status**: resolved
**Area**: infra

### Summary
A multi-file `apply_patch` operation rejected pure move hunks that contained no context or changed lines.

### Error
```
apply_patch verification failed: invalid hunk at line 2,
Update file hunk for path 'Sources/MacTools/MacToolsMain.swift' is empty
```

### Context
- The task needs Git-recognizable source moves while preserving executable behavior.
- The rejected patch contained only `Update File` and `Move to` markers.
- The patch was rejected atomically, so no source file was partially moved.

### Suggested Fix
Include a small in-scope comment update in each move hunk, such as correcting the file-level responsibility after
the directory boundary changes.

### Metadata
- Reproducible: yes
- Related Files: Sources/MacTools, Sources/MacToolsCore/UI

### Resolution
- **Resolved**: 2026-07-29T16:00:00+08:00
- **Notes**: Replaced content-free moves with atomic moves that also update file-level responsibility comments.

---

## [ERR-20260729-003] zsh parsed a quoted secret-scan regular expression as a glob

**Logged**: 2026-07-29T15:52:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tooling

### Summary
A supplemental high-risk credential scan failed before execution because nested single quotes ended the shell-quoted
PCRE expression and exposed the remaining pattern to zsh glob parsing.

### Error
```
zsh:1: bad pattern
```

### Context
- The repository's required broad sensitive-word scan had already completed.
- The failed command was an additional literal-format scan and did not modify source files.
- The expression included a character class containing both quote types inside a single-quoted shell argument.

### Suggested Fix
Run complex credential patterns inside a Ruby heredoc so the regular expression is parsed by Ruby rather than
re-escaped through the shell.

### Metadata
- Reproducible: yes
- Related Files: .learnings/ERRORS.md

### Resolution
- **Resolved**: 2026-07-29T15:52:00+08:00
- **Notes**: Replaced the shell-quoted PCRE command with an equivalent read-only Ruby scanner.

---

## [ERR-20260730-001] performance skill referenced a missing checklist

**Logged**: 2026-07-30T17:20:35+08:00
**Priority**: low
**Status**: resolved
**Area**: docs

### Summary
The performance optimization skill references a detailed checklist that is absent from the installed skill package.

### Error
```
sed: /Users/bytedance/.codex/skills/performance-optimization/references/performance-checklist.md: No such file or directory
```

### Context
- Attempted to load the skill's linked checklist before auditing the macOS application.
- The main `SKILL.md` was available and complete.
- The missing reference is outside this repository and does not block source inspection or runtime measurement.

### Suggested Fix
Restore `references/performance-checklist.md` in the installed performance skill package or remove the stale reference.

### Metadata
- Reproducible: yes
- Related Files: /Users/bytedance/.codex/skills/performance-optimization/SKILL.md

### Resolution
- **Resolved**: 2026-07-30T17:20:35+08:00
- **Notes**: Continued with the main performance workflow and a Swift/macOS-specific audit.

---

## [ERR-20260730-002] performance audit probes assumed unsupported fields and stale paths

**Logged**: 2026-07-30T17:20:35+08:00
**Priority**: medium
**Status**: resolved
**Area**: tooling

### Summary
Several read-only performance probes initially assumed Linux-style `ps` fields, guessed source paths, emitted
unbounded heap output, or targeted the legacy clipboard database name instead of the unified Store path.

### Error
```
ps: thcount: keyword not found
ps: nlwp: keyword not found
nl: Sources/MacToolsCore/Utilities/ImageDataNormalizer.swift: No such file or directory
rg: Sources/MacToolsCore/Store: No such file or directory
Error: in prepare, no such table: clipboard_items
```

### Context
- The host uses the macOS BSD `ps`, whose supported output keywords differ from Linux and from some older macOS examples.
- `ImageDataNormalizer` belongs to `MacToolsCore/Clipboard`, and storage code belongs to
  `MacToolsCore/Storage`.
- The active database path is defined by `MacToolsStorePaths.databaseURL` as `Store/mactools.sqlite3`;
  `Clipboard.sqlite` is only the legacy migration source.
- An unconstrained `heap`/`leaks` batch exceeded the tool output budget before the probes were rerun with
  filtered output.

### Suggested Fix
Resolve paths with `rg --files`, inspect `MacToolsStorePaths` and SQLite `.tables` before querying, use only
verified BSD `ps` fields, and cap diagnostic output at the command boundary.

### Metadata
- Reproducible: yes
- Related Files: Sources/MacToolsCore/Storage/MacToolsStorePaths.swift,
  Sources/MacToolsCore/Clipboard/ImageDataNormalizer.swift

### Resolution
- **Resolved**: 2026-07-30T17:20:35+08:00
- **Notes**: Re-ran the probes against the verified paths, used supported `ps` fields, and constrained heap and
  leak summaries.

---

## [ERR-20260805-001] runtime database probe queried an unverified table name

**Logged**: 2026-08-05T18:11:44+08:00
**Priority**: low
**Status**: resolved
**Area**: tooling

### Summary
A read-only runtime diagnostic queried `payload_refs` even though the active unified database uses
`payload_objects`.

### Error
```
Error: in prepare, no such table: payload_refs
```

### Context
- The probe was collecting only storage counts while investigating a MacTools resource stall.
- The same command printed `.tables`, but issued the aggregate query before adapting it to the observed schema.
- The failed statement was read-only and did not modify application data.

### Suggested Fix
Run SQLite schema discovery in a separate command, then build follow-up read-only queries exclusively from the
verified table list.

### Metadata
- Reproducible: yes
- Related Files: Sources/MacToolsCore/Storage/ClipboardDatabase.swift
- See Also: ERR-20260730-002

### Resolution
- **Resolved**: 2026-08-05T18:11:44+08:00
- **Notes**: Re-ran the aggregate using the verified `payload_objects` table and raised the linked recurring
  diagnostic mistake to medium priority.

---

## [ERR-20260805-002] diagnostic classifier used prohibited temporary-file cleanup

**Logged**: 2026-08-05T18:11:44+08:00
**Priority**: medium
**Status**: resolved
**Area**: tooling

### Summary
A read-only log-classification command was rejected because its temporary-file cleanup used `rm -f`.

### Error
```
rm -f style commands are not permitted. Use a safer approach
```

### Context
- The command intended to store a fixed list of safe log prefixes in a `mktemp` file.
- No project or runtime file was changed or deleted because the command was rejected before launch.

### Suggested Fix
Use an inline Ruby or shell array classifier that reads the existing log without creating temporary files.

### Metadata
- Reproducible: yes
- Related Files: .learnings/ERRORS.md

### Resolution
- **Resolved**: 2026-08-05T18:11:44+08:00
- **Notes**: Replaced the temporary-file pipeline with an inline, read-only Ruby classifier. The same prohibited
  cleanup pattern recurred on 2026-08-06 while aggregating lock-screen performance logs; use a direct stream
  processor with no temporary file for all follow-up diagnostics.

---

## [ERR-20260805-003] SwiftPM manifest library does not match the active compiler

**Logged**: 2026-08-05T18:19:07+08:00
**Priority**: medium
**Status**: pending
**Area**: tooling

### Summary
Focused tests could not start because the active Command Line Tools installation links the package manifest
against an incompatible `PackageDescription` library.

### Error
```
error: 'mytools': Invalid manifest
Undefined symbols for architecture arm64:
  PackageDescription.Package.__allocating_init(...)

/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap:13:8:
error: redefinition of module 'SwiftBridging'
```

### Context
- `xcode-select -p` resolves to `/Library/Developer/CommandLineTools`.
- The active compiler reports Apple Swift 6.1.2 and targets macOS 16.0.
- The failure occurs while linking `Package.swift`, before project sources or tests compile.
- A standalone frontend parse is also blocked by duplicate `SwiftBridging` module maps in the same toolchain.
- No additional dependency or toolchain was installed during diagnosis.

### Suggested Fix
Repair or reinstall a matching Apple Command Line Tools/Xcode toolchain, then rerun the focused SwiftPM tests.

### Metadata
- Reproducible: yes
- Related Files: Package.swift

---

## [ERR-20260806-001] AppleScript window-layout shortcut injection denied

**Logged**: 2026-08-06T15:20:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tests

### Summary
The shell could not inject window-layout shortcuts into Chrome during packaged-app verification because macOS denied synthetic keyboard events.

### Error
```
“System Events”遇到一个错误：“osascript”不允许发送按键。 (1002)
```

### Context
- Built and launched the packaged `build/MacTools.app`, then attempted a reversible Chrome bounds check.
- The current `osascript` process does not have Accessibility permission to send keyboard input.
- The command stopped before sending a shortcut or modifying the Chrome window.

### Suggested Fix
Keep the real Chrome shortcut sequence in `docs/manual-verification.md`; run it through physical user input or a terminal process that already has explicit Accessibility permission. Do not alter TCC permissions during automated verification.

### Metadata
- Reproducible: yes
- Related Files: docs/manual-verification.md, scripts/rebuild_and_run_app.sh
- See Also: ERR-20260716-001, ERR-20260728-011

### Resolution
- **Resolved**: 2026-08-06T15:20:00+08:00
- **Notes**: Stopped synthetic input automation, retained the packaged build result, and left the Chrome transition sequence as an explicit manual verification boundary.

---

## [ERR-20260806-002] zsh reserved path parameter shadowed PATH

**Logged**: 2026-08-06T09:14:02Z
**Priority**: low
**Status**: resolved
**Area**: docs

### Summary
A zsh validation loop used `path` as its iterator variable, which replaced the shell's special `path` array and made subsequent commands unavailable.

### Error
```
zsh:10: command not found: git
```

### Context
- The command checked whether paths referenced by an update design document existed.
- In zsh, `path` is tied to the `PATH` environment variable.
- The loop completed without changing project files, then `git add`, `git diff`, and `git status` could not start.

### Suggested Fix
Use a non-special iterator such as `referenced_path` in zsh loops and start the follow-up validation in a fresh shell.

### Metadata
- Reproducible: yes
- Related Files: docs/superpowers/specs/2026-08-06-github-sparkle-update-design.md

### Resolution
- **Resolved**: 2026-08-06T09:14:02Z
- **Notes**: Replaced the iterator with `referenced_path`; no source or index state needed recovery.

---
