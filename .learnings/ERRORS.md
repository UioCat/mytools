# Errors

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
