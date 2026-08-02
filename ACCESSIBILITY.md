# Accessibility

Logic Lyrics targets practical macOS accessibility across VoiceOver, keyboard use, display accommodations and clear error recovery.

## Implemented behavior

- Icon-only controls have explicit VoiceOver labels and hints; decorative icons are hidden.
- BPM, key, alternative, lyrics and section-copy actions expose semantic labels.
- File selection is available through buttons and **File → Open Logic Pro Project…** (`Command-O`); drag and drop is never the only path.
- Complete lyrics can be copied with `Shift-Command-C` or a labelled button.
- Processing state is announced and retains a Cancel control.
- Reduce Motion disables decorative transitions; Reduce Transparency replaces translucent surfaces.
- Status never relies on color alone, selectable text uses native macOS behavior, and controls use native focus rings.
- Stable accessibility identifiers cover the picker, reader, clipboard actions, recent projects and window-layout tests.
- CI runs semantic VoiceOver audits, control-alignment assertions and compact/large screenshots.

## Release checklist

Before release, test the oldest supported and current macOS versions with:

1. VoiceOver navigation from empty launch through File-menu import, metadata reading, full-lyrics copy, section copy and recent-project reopening.
2. Full Keyboard Access with no mouse or drag and drop.
3. Reduce Motion and Reduce Transparency.
4. Increased contrast and large display text.
5. Empty notes, unreadable project, cancellation and long localized strings.

Automated XCUITest audits reduce regressions but do not replace real assistive-technology testing.
