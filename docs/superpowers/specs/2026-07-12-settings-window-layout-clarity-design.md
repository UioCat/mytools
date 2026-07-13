# Settings Window Layout Clarity Design

**Status:** Approved direction A — pending implementation-plan review

## Goal

Make the Settings page’s window-layout editor easy to scan and use at wide desktop sizes:

1. Every miniature preview must make its represented screen region clear at a glance.
2. The page must use the available content width instead of leaving a conspicuous empty area to the right of the settings content.

## Intent

- **Person and task:** A Mac power user is configuring frequent window-placement actions and their shortcuts. They need to compare left/right and one-third/two-third choices quickly, without reading each label twice.
- **Feel:** A calm, precise macOS control surface: the existing translucent glass remains quiet while window-placement geometry is immediately legible.
- **Focal element:** Each layout action cell. Its preview must communicate the target region before the user reads its title; the toggle and shortcut remain secondary controls.

## Product Direction

- **Domain:** desktop window management, screen edges, split panes, keyboard control, active placement region, spatial configuration.
- **Color world:** macOS window-gray, recessed screen gray, blue selection tint, white inactive canvas, graphite text, soft divider gray.
- **Signature:** Each action card uses a miniature screen with a stable neutral frame and a single saturated blue placement region. The blue region is the configuration’s spatial shorthand, not decoration.
- **Rejecting:** barely visible translucent rectangles, a narrow fixed-width editor floating in a wide page, and a full-page single-column form that would make simple settings overly sparse.

## Layout

The settings page retains its current two-column arrangement for lightweight sections such as shortcuts, clipboard, translation, permissions, and system controls. This keeps related values compact and scannable.

The Window Layout section becomes the page’s full-width editing zone. It fills the Settings page’s available inner width rather than using the existing fixed 774-point ceiling. Each semantic group (half, one-third, two-thirds, focus) stays in a horizontal two-card row:

- the group name remains a compact leading label;
- the two action cards split the remaining row width evenly;
- the cards grow with the page, so title, toggle, shortcut field, and remove affordance no longer compete for a narrow column;
- the narrow fallback remains a vertically stacked layout for compact windows.

This preserves the established hierarchy: general application settings above, then the more spatial, hands-on layout editor across the full content surface.

## Preview Treatment

Each layout action preview will use a small, consistently sized miniature screen:

- a clearly visible neutral screen fill and 1-point low-contrast outline establish the full available display;
- the target placement is a stronger system-blue rectangle with a subtle blue outline, so its size and left/right position remain legible on light glass;
- a small internal inset keeps the active region visually distinct from the screen boundary, including the maximum layout;
- disabled action cells retain the geometry but use the existing muted hierarchy rather than reducing contrast so far that the preview disappears.

No action behavior, ordering, shortcut validation, enablement logic, or persistence model changes.

## Component Boundaries

- `SettingsView` owns responsive page and editor-width composition.
- `WindowLayoutSettingsEditor` continues to own settings draft state and persistence callbacks.
- `WindowLayoutModeActionCell` owns the action-cell arrangement and supplies its mode to a focused preview subview.
- A small private preview subview owns only neutral-screen and active-region rendering, drawing from the existing `WindowLayoutMode.previewSegment` data.

The split keeps screen geometry reusable and testable without moving settings behavior out of its current feature boundary.

## Visual System

- **Palette:** existing adaptive glass/text tokens for surfaces and typography; system blue only for the selected layout region and enabled switch state.
- **Depth:** retain the existing quiet glass-module and divider strategy—no heavy card borders or new shadows.
- **Typography:** keep current 12–13 point labels and shortcut hierarchy; preview gains recognition through contrast and geometry, not oversized text.
- **Spacing:** preserve the 8-point rhythm with 14-point group/card spacing and aligned inner padding. The wider editor distributes space to content rather than creating larger empty gutters.
- **States:** enabled, disabled, hover/focus, toggled presentation, assigned shortcut, and shortcut removal retain their present interactions and accessibility labels. The preview must be recognizable in all non-disabled states.

## Acceptance Criteria

- On a wide Settings window, no prominent blank region remains to the right of the settings content because the Window Layout editor grows to the usable inner width.
- All eight built-in layout previews have visibly distinguishable neutral screen frames and blue target regions; left/right and one-third/two-third variants can be recognized without reading the text label.
- The Window Layout editor retains grouped two-card rows at normal desktop width and degrades to the existing stacked layout when horizontal space is constrained.
- Existing layout mode grouping, shortcut conflict validation, action order, persistence, toggles, and disabled behavior remain unchanged.
- Focused automated regression tests cover the preview geometry/style contract and wide/narrow layout-selection policy before implementation code is written.
- `swift test` passes, then `scripts/rebuild_and_run_app.sh` is run and the affected Settings surface is inspected on contrasting light and dark backgrounds for legibility and glass-edge regressions.

## Non-goals

- Redesigning the settings header, sidebar, or unrelated settings sections.
- Changing layout actions or their configuration schema.
- Introducing a new color system, a new navigation model, or external dependencies.
