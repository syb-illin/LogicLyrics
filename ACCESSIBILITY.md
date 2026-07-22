# Accessibility

Logic Lyrics targets practical macOS accessibility across VoiceOver, keyboard use, display accommodations, and clear error recovery.

## Implemented behavior

- Meaningful icon-only controls have explicit VoiceOver labels and hints.
- Decorative icons are hidden from the accessibility tree.
- BPM, key, technical audio values, section-copy actions, artwork state, lyrics, and generated prompts expose semantic labels.
- Related status content is combined into concise VoiceOver elements.
- File selection is available through buttons and keyboard commands; drag and drop is never the only path.
- Primary shortcuts include Open (`Command-O`), Copy All (`Shift-Command-C`), history (`Shift-Command-H`), prompt generation (`Command-Return`), and diagnostics (`Option-Command-D`).
- Processing overlays announce their state and retain a Cancel control.
- Reduce Motion disables decorative animation.
- Reduce Transparency replaces material backgrounds with opaque surfaces.
- Success and error states use text/icons in addition to color.
- Editors support selection, editing, and standard macOS text navigation.
- Controls use native SwiftUI components so focus rings, contrast adaptation, and keyboard behavior follow macOS conventions.
- Stable accessibility identifiers cover history navigation, transfer actions, project recovery, revisions, and window-layout smoke tests.
- CI runs semantic element-description/detection audits and captures migrated-history screenshots at compact and large window sizes.

## Release checklist

Before release, test on the oldest supported macOS version and the current macOS version with:

1. VoiceOver navigation from an empty launch through Logic import, lyrics editing, section copying, Suno prompt creation, history, and audio metadata.
2. Full Keyboard Access with no mouse or drag-and-drop.
3. Reduce Motion and Reduce Transparency enabled.
4. Increased contrast and a large display text setting.
5. Light/dark appearance if the app later stops enforcing its current dark presentation.
6. Error, cancellation, empty-state, and long-localized-string paths.

Automated XCUITest audits and semantic modifiers reduce regressions, but they do not replace assistive-technology testing with real workflows.
