# Changelog

All notable user-facing changes are documented here. Releases use semantic versions and every shipped build receives a new build number.

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
