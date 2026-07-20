# Super Right-Click Replay Loop Fix Design

## Goal

Prevent a short super-right-click from re-entering MacTools' own event tap while preserving both existing user-visible outcomes:

- A short right-click opens the normal macOS context menu.
- A long right-click suppresses the system menu and triggers the MacTools panel once.

The fix must remain reliable while other mouse utilities, including uTools and Logi Options+, have active HID event taps.

## Root Cause

`SuperRightClickMonitor` installs an active event tap at the session entry point. It suppresses the original short right-click, copies the down and up events, marks them through `eventSourceUserData`, and posts them again at the HID entry point.

Posting at the HID entry point sends the copied events through every earlier HID filter before they return to the MacTools session tap. Another filter can replace or rewrite an event and remove the marker. MacTools then treats its own replay as a new short right-click and repeats the replay indefinitely. Runtime evidence showed thousands of MacTools right-click callbacks for only tens of WindowServer button-state changes, with the loop ending when the app or login session reset.

## Approaches Considered

1. **Replay after the current event tap — selected.** Pass the callback's `CGEventTapProxy` through the monitor and use `CGEvent.tapPostEvent(_:)`. Core Graphics then delivers the replay only to taps after MacTools, so it cannot directly re-enter the MacTools tap or traverse earlier HID filters.
2. **Disable the tap around HID replay.** This introduces a race in which real input can bypass the monitor and requires careful re-enablement on every error path.
3. **Keep HID replay with stronger markers and rate limiting.** Third-party filters can still rewrite all chosen event fields, while a rate threshold could suppress legitimate input and would mask rather than remove the replay cycle.

## Event Flow

The event-tap callback retains its existing synchronous main-actor routing and additionally passes its `CGEventTapProxy` to the right-button-up handler.

For a short press:

1. Suppress and retain a copy of the original right-button-down event.
2. Suppress the original right-button-up event.
3. Copy the retained down event and current up event.
4. Post the down copy and then the up copy through `tapPostEvent(proxy)`.
5. Clear the pending down event.

Events posted with the proxy continue after the current session tap. Taps later in the event stream and the target application still receive the normal down/up pair, but MacTools and earlier HID taps do not receive that replay.

The long-press timer, selection capture, panel presentation, event-tap enablement, and settings behavior remain unchanged.

## Implementation Boundaries

- Keep Core Graphics integration in `Sources/MacTools/App/SuperRightClickMonitor.swift`.
- Do not add a new abstraction to `MacToolsCore`; the change is a direct event-tap integration correction with no reusable domain policy.
- Remove the `eventSourceUserData` replay marker and its helper methods after the HID replay path is gone.
- Do not add an arbitrary event-rate circuit breaker. The selected insertion point removes the feedback path without changing valid click rates.
- Do not change the configured long-press thresholds or permission requirements.

## Error Handling

If either event copy cannot be created, keep the existing safe failure behavior: emit the non-sensitive replay error, clear the pending event, and do not synthesize a partial click pair.

System event-tap disable notifications continue to re-enable the installed tap as they do today. No error path may retain a stale pending right-button-down event after the corresponding button-up callback.

## Testing and Verification

- Add a focused source-contract regression test that fails while the monitor posts at `.cghidEventTap` and passes only when both replay events use `tapPostEvent(proxy)` with the callback proxy.
- Keep the existing `RightClickStateMachineTests` passing to prove short- and long-press routing is unchanged.
- Run the focused regression tests, then the complete `swift test` suite.
- Build and launch the packaged app because event-tap permissions and identity are not represented by `swift run`.
- With uTools and Logi Options+ still active, inject one sub-threshold right-click and confirm the debug log records one down/up pair with no repeated callbacks during the following two seconds.
- Manually confirm a short press still opens the system menu and a long press triggers the MacTools panel once without opening the system menu.
- Run `git diff --check` and the repository secret scan before completion.

## Success Criteria

- No short right-click produces an unbounded callback sequence.
- Short and long right-click product contracts remain unchanged.
- Runtime verification succeeds with the currently installed uTools and Logi Options+ event taps active.
- No unrelated source, settings, synchronization, clipboard, or UI behavior changes.
