# Contributing to Logic Lyrics

Thank you for helping make Logic Lyrics safer and more useful for musicians. Focused bug reports, accessibility findings, compatibility samples and small, reviewable pull requests are especially valuable.

## Before opening an issue

1. Search existing issues and Discussions.
2. Confirm the problem on the latest release when possible.
3. Remove lyrics, artist names, project names, paths and other private material from screenshots or logs.
4. Use the bug or feature form so the report contains the information needed to act on it.

Use a private security report for vulnerabilities; see [SECURITY.md](SECURITY.md).

## Development setup

Logic Lyrics targets macOS 14 or later and is written in Swift and SwiftUI.

- Lightweight path: double-click `BUILD.command` with Apple Command Line Tools installed.
- IDE path: open `LogicLyrics.xcodeproj` in Xcode 16 or later.
- Regression tests: `swift Tests/CoreRegressionTests.swift`
- GitHub dashboard tests: `python3 -m unittest discover -s Tools/GitHubStats -p 'test_*.py' -v`

The build uses strict Swift concurrency checking. Read [ARCHITECTURE.md](ARCHITECTURE.md) before changing project parsing, project writing, update installation, history persistence or audio metadata behavior.

## Pull requests

- Keep each pull request focused on one problem.
- Add or update regression coverage for behavior changes.
- Preserve originals: Logic projects and audio files must only be written to a new copy.
- Keep file parsing and network work away from the main actor.
- Never add analytics that collect lyrics, prompts, audio, project names, file names, paths or personal identifiers.
- Localize visible strings in English and French.
- Verify keyboard navigation, VoiceOver labels, contrast, Reduce Motion and non-color-only state communication.
- Increment the build number for every shipped build and the semantic version for every release.

Explain the user impact, validation performed and any remaining limitation in the pull request description.

## Compatibility samples

Logic project internals are undocumented and can differ by Logic Pro version. Never attach a private production project to a public issue. Create the smallest possible synthetic project, remove audio and personal metadata, then state the Logic Pro and macOS versions used.

## Community behavior

Participation is governed by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Be direct, patient and respectful; assume reports come from people trying to protect real creative work.
