# Logic Lyrics 2.6.0 — architecture and invariants

## Product boundary

Logic Lyrics has one responsibility: read a selected alternative of a local `.logicx` project and present its Project Notes, BPM, key and section markers for clipboard use. It does not modify Logic projects, process audio, call generative AI or send application telemetry.

## Layers

- **Model** contains immutable, `Sendable` domain values and deterministic section parsing.
- **Services** contain Logic package parsing, project bookmark resolution, versioned history persistence and GitHub release lookup.
- **ViewModel** is a `MainActor`-isolated state machine that coordinates one replaceable Logic-read operation.
- **Views** are split into composition (`ContentView`), recent projects (`RecentProjectsView`) and read-only lyrics presentation (`LyricsReaderView`).
- **App commands** inject the File-menu action through SwiftUI focused values instead of notifications or global mutable UI state.

This is intentionally small MVVM with ports at external boundaries. Value types are preferred; classes are reserved for observable identity and actor-isolated state.

## Applied patterns

- **MVVM** separates parsing/orchestration from SwiftUI rendering.
- **Repository actor** serializes atomic schema-5 history reads, migrations and writes.
- **Dependency inversion** exposes only `LogicProjectReading` to the presentation model.
- **State machine + operation identity** makes progress, cancellation and stale-result rejection explicit.
- **Adapter** confines GitHub HTTP/JSON behavior to `GitHubReleaseClient`.
- **Project locator** encapsulates filesystem identity and security-scoped bookmark recovery.
- **Focused command injection** routes `Command-O` to the active scene.
- **Source-state token** detects external changes from file metadata without polling or rescanning ProjectData.
- **Transactional install** stages replacement, preserves the prior app and rolls back on any post-backup failure.
- **Design system** centralizes restrained surfaces, icon treatment, status chips and accessibility accommodations.

## Safety and performance invariants

1. Source `.logicx` packages are never written or replaced.
2. The active Logic alternative is selected by default; explicit alternative changes re-read only that alternative and unrelated single-line technical RTF is rejected.
3. Mapped `Data` avoids an unnecessary full byte-array copy while scanning `ProjectData`.
4. Parser loops check cooperative cancellation at bounded intervals.
5. An operation UUID prevents an older read from overwriting a newer project selection.
6. Owned tasks are cancelled on replacement and object destruction; detached work captures view models weakly.
7. Section identifiers are deterministic within a document, preventing avoidable SwiftUI row churn.
8. History is loaded and saved by an actor, encoded atomically and protected against the initial-load/save race.
9. History uses stable file identity and security-scoped bookmarks to recover moved or renamed projects.
10. Logs never contain lyrics, names, filenames, paths, URLs, bookmarks or other user content.
11. Diagnostic log export is limited to this process, the last 30 minutes and at most 200 entries.
12. User-impacting failures surface through accessible alerts; normal picker cancellation remains silent.
13. Schema 5 contains no prompt, editor or recovered-revision domains; the untouched schema-4 file is backed up before migration.
14. The app sandbox grants user-selected read-only access, while bookmarks retain explicit access to previously chosen projects.
15. Update approval is bound to exact release asset URLs and an expected semantic version, then checksum- and manifest-verified.

No static review can mathematically prove the absence of every runtime leak. Release validation therefore combines complete strict-concurrency compilation, cancellation tests, repeated UI workflows and recommended Instruments runs with Leaks, Allocations and Time Profiler.

## Build validation

`BUILD.command`:

- requires only Apple Command Line Tools;
- rejects any Swift application file omitted from its explicit source manifest;
- compiles with complete strict-concurrency checking and warnings;
- runs reader/history/locator/view-model/update and transactional-install regression tests before building the app;
- validates localizations and `Info.plist`;
- signs and verifies the final bundle;
- optionally notarizes and staples Developer ID builds.

GitHub Actions runs the same lightweight build, then executes native File-menu/picker, recent-project navigation, clipboard, VoiceOver, alignment and compact/large-window UI tests. Tagged runs publish checksummed app and source archives.
