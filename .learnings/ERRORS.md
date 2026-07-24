# Errors

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
- **Notes**: 改用不创建临时文件的证书用途、有效期和身份策略检查。

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
