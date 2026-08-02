# Changelog

All notable user-facing changes are documented here. Releases use semantic versions and every shipped build receives a new build number.

## 2.5.1 — build 35

- Fixed recent-project search so it matches project names only instead of silently matching text buried in current or recovered lyrics.
- Added a native **No lyrics** checkbox that filters projects whose current Logic Project Notes are empty and composes with title search.
- Updated the result count live while filtering and renamed the history action to the clearer **Open Logic Project**.
- Added pure policy and macOS UI regressions for title-only matching, lyrics-only false positives, empty Project Notes, combined filters, result counts, and the action label.
- Added automated English/French localization-key parity and a French VoiceOver/UI regression for the new controls.
- Enforced localization across every SwiftUI surface and audited the empty workspace, lyrics history, no-lyrics state, Settings, About, VoiceOver semantics, and window sizes in English and French.
- Replaced low-contrast secondary caption styling with an adaptive accessible text palette and made multilingual UI-test startup detection resilient.
- Made the main scene reliably reopen in every language while preserving a single-window workflow, with native macOS audits plus deterministic accessible-name validation for every interactive control.
- Gives the result count a native static-text role, increases Settings caption legibility, and renders the bundled French catalog deterministically in macOS UI tests without changing production locale behavior.
- Uses guaranteed high-contrast text on the app’s dark surfaces and gives Settings the same explicit dark appearance as the main workspace.
- Replaces translucent reading surfaces with visually equivalent opaque surfaces so assistive contrast analysis is deterministic across every open app window.
- Increased small status, result-count, and empty-state typography contrast, and gave every recent-song control an explicit localized VoiceOver label.
- Added an independent pixel-level WCAG AA contrast measurement so macOS XCTest false positives are accepted only when the rendered UI proves a ratio of at least 4.5:1.
- Forced the matching dark AppKit appearance for native title bars and replaced each visual history row with one explicit, localized VoiceOver button representation.
- Removed the redundant low-contrast native navigation title and verifies that every history row maps to a labelled button.
- Requires readable labels for every product-owned interactive element while recognizing macOS traffic-light controls by their stable native accessibility identifiers.
- Gives the sidebar’s icon-only command an explicit tested identity and keeps every app-identified control subject to the accessible-name gate while leaving anonymous AppKit implementation controls to the native element-detection audit.
- Excludes only zero-area hidden AppKit menu proxies from the visible-control name check; opened File and About menu actions remain covered by dedicated UI scenarios.

## 2.5.0 — build 34

- Refocused Logic Lyrics on one job: reading `.logicx` Project Notes, tempo, key and section markers, then copying the lyrics.
- Replaced the multi-tool workspace with a restrained read-only lyrics interface and a simpler recent-project sidebar.
- Removed Suno prompt generation, audio metadata/tagging, MP3 conversion, LAME, and experimental Logic-project writing from the product and build.
- Split recent-project and lyrics rendering into focused SwiftUI components and narrowed the injected service boundary to Logic reading.
- Added lifecycle cancellation for owned tasks, stable section identities, source-manifest validation, and bounded privacy-safe Unified Log diagnostics.
- Updated File-menu, clipboard, VoiceOver, control-alignment and compact/large-window UI coverage for the focused reader.

## 2.4.1 — build 33

- Added the native **File → Open Logic Pro Project…** command with the standard ⌘O shortcut and the existing sandboxed `.logicx` picker.
- Reworked the visual system around restrained macOS surfaces, native typography, consistent spacing, muted colors, and aligned action controls.
- Added UI regression coverage that invokes the File menu, verifies the project picker, and checks history-action alignment.
- Added privacy-safe UI diagnostics and treated file-picker cancellation as a normal, silent user action.

## 2.4.0 — build 32

- Added stable filesystem identity and security-scoped bookmarks so history follows Logic projects after moves and renames.
- Added **Open Project**, **Locate Project**, revision restoration, and safe revert-to-project actions to history details.
- Added portable, capability-stripped history export and defensive merge-based import with transactional writes and visible progress.
- Added automated macOS UI coverage for history navigation, migrated visual states, accessibility audits, and compact/large window layouts.
- Expanded core regression coverage for bookmark resolution, renamed-project consolidation, revision recovery, and portable archive round trips.

## 2.3.0 — build 31

- Added a permanent, searchable **Recent Songs** list to the sidebar, available across launches even when no project is open.
- Migrated history to schema 3 with one row per Logic project, separate Logic-source and locally edited lyrics, and lossless recovery of older duplicate values.
- Prevented initial history loading, project navigation, and debounced editor saves from overwriting one another.
- Added regression coverage for legacy migration, duplicate consolidation, source/edit separation, and the asynchronous startup race.
- Replaced the app icon with a fully opaque, full-mask monochrome design whose waveform remains legible at small macOS sizes.

## 2.2.5 — build 30

- Fixed cached history replacing freshly extracted Project Notes after a Logic project opens.
- Made the open Logic project the immutable source of truth for each new editor session while preserving history as a separate workspace.
- Added an asynchronous view-model regression test covering the complete reader-to-editor handoff.

## 2.2.4 — build 29

- Fixed Project Notes detection in Logic projects containing unrelated rich-text loop and region metadata.
- Read lyrics, BPM and musical key from the active Logic alternative instead of an older alternative.
- Added regression coverage for active-alternative selection and technical RTF false positives.

## 2.2.3 — build 28

- Added a product-focused GitHub Pages landing page while preserving repository analytics under `/stats/`.
- Rebuilt the repository README around the Logic Pro-to-Suno workflow, privacy guarantees and direct app download.
- Added repository contribution, support, security, conduct, roadmap, issue and pull request guidance.
- Added a restrained 1280 × 640 social preview asset and richer search/social metadata.
- Published the source under the MIT License.

## 2.2.2 — build 27

- Added a privacy-safe GitHub statistics dashboard with persistent release-download history.
- Added optional GitHub Traffic collection through a read-only repository secret.

## 2.2.1 — build 26

- Added configurable automatic update checks and a visible manual **Check Now** result.

## 2.2.0 — build 25

- Added audio metadata workflows, MP3 conversion, bilingual UI, accessibility support, diagnostics and safer update handling.
