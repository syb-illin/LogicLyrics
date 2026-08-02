# Accessibility

Logic Lyrics targets practical macOS accessibility across VoiceOver, keyboard use, display accommodations and clear error recovery.

## Implemented behavior

- Icon-only controls have explicit VoiceOver labels and hints; decorative icons are hidden.
- BPM, key, alternative, lyrics and section-copy actions expose semantic labels.
- File selection is available through buttons and **File → Open Logic Pro Project…** (`Command-O`); drag and drop is never the only path.
- Complete lyrics and each detected section have labelled clipboard actions.
- Lyrics refresh is available through a labelled button and **File → Refresh Lyrics** (`Command-R`).
- History pin, Finder, Logic Pro and removal actions are exposed as native menus with explicit accessible names.
- Processing state is announced and retains a Cancel control.
- Reduce Motion disables decorative transitions; Reduce Transparency replaces translucent surfaces.
- Status never relies on color alone, selectable text uses native macOS behavior, and controls use native focus rings.
- Stable accessibility identifiers cover the picker, reader, clipboard actions, recent projects and window-layout tests.
- CI runs semantic accessibility audits, control-alignment assertions, history-management scenarios and compact/large visual snapshots.

## Manual VoiceOver release protocol

Automation cannot drive or evaluate the VoiceOver speech stream. Before tagging
a release, a maintainer records the date, macOS version, hardware, app version
and pass/fail result for each step below in the release notes or release PR:

1. Enable VoiceOver before launch; navigate from the app title to Open, Recent Projects and the empty workspace without a mouse.
2. Open a `.logicx` project with `Command-O`; confirm project name, BPM, key, alternative, stale status and extraction diagnostics are announced in reading order.
3. Change alternatives, refresh with `Command-R`, copy all lyrics and copy one section; confirm every action announces its result once.
4. Pin and unpin a history row, reveal it in Finder, open it in Logic Pro, cancel removal, then confirm removal.
5. Use the no-lyrics filter and title search; confirm result-count changes and empty results are announced.
6. Repeat the workflow in English and French with Full Keyboard Access enabled.
7. Repeat the compact-window path with Reduce Motion, Reduce Transparency, Increase Contrast and a larger display scale.
8. Verify focus returns to a safe control after picker cancellation, an unreadable project alert, and every destructive confirmation.

The release sign-off must name the tester. A missing or failed manual sign-off
blocks the release even when XCUITest is green.

Automated XCUITest audits reduce regressions but do not replace real assistive-technology testing.
