# Learnings

## [LRN-20260714-001] correction

**Logged**: 2026-07-14T19:54:00+08:00
**Priority**: high
**Status**: resolved
**Area**: backend

### Summary
Odd H.264 dimensions were not the cause of AVFoundation `-16122`; incomplete ScreenCaptureKit frames are the supported root-cause direction.

### Details
An independent `AVAssetWriter` probe successfully wrote both `401 × 301` and `400 × 300` H.264 MP4 files. A second probe appended a sample that was valid and data-ready but had no image buffer; it reproduced `AVFoundationErrorDomain -11800` with underlying status `-16122` exactly. Apple’s ScreenCaptureKit sample requires checking for `SCFrameStatus.complete` and a non-nil image buffer before processing a frame, while the recorder previously appended every data-ready sample.

### Suggested Action
Validate ScreenCaptureKit frame status and image-buffer presence before appending to `AVAssetWriter`, and use minimal media probes before assuming encoder dimension restrictions.

### Metadata
- Source: error
- Related Files: Sources/MacTools/App/ScreenCapture/MP4ScreenRecorder.swift
- Tags: avfoundation, screencapturekit, debugging

### Resolution
- **Resolved**: 2026-07-14T19:54:00+08:00
- **Notes**: Replaced the dimension workaround with complete-frame validation.

---

## [LRN-20260714-002] correction

**Logged**: 2026-07-14T21:00:39+08:00
**Priority**: medium
**Status**: resolved
**Area**: frontend

### Summary
For visual exploration, “similar feeling” means preserve mood and rendering language, not the reference image's subject geometry.

### Details
The requested app-icon follow-up used a translucent ribbon reference. Generating ten new ribbon folds kept the image too similar even though the geometry changed. The correct interpretation is to preserve only the dark restrained background, cyan-blue-violet glass palette, soft glow, premium macOS finish, and single-symbol simplicity while exploring clearly different metaphors and silhouettes.

### Suggested Action
When a user asks for the same feeling, explicitly classify the reference as a mood/material reference, list the retained style attributes, and vary the central object, silhouette, negative space, and metaphor across concepts.

### Metadata
- Source: user_feedback
- Related Files: N/A
- Tags: imagegen, icon-design, visual-reference, concept-diversity

### Resolution
- **Resolved**: 2026-07-14T21:00:39+08:00
- **Notes**: Regenerated the set from ten distinct icon metaphors while retaining only the reference image's visual mood.

---
