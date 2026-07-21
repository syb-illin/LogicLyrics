# Logic Lyrics 2.2.1 — architecture and invariants

## Layers

- `Model`: immutable values and domain state without UI dependencies.
- `Services`: Logic parsing/writing, audio inspection/tagging, MP3 conversion, updates, and persistence.
- `ServiceProtocols`: injectable ports used by view models and regression tests.
- `ViewModel`: `MainActor`-isolated presentation state, validation, and orchestration.
- `Views`: SwiftUI rendering and user interaction only.

This is a pragmatic MVVM/service architecture. Protocol-based dependency inversion keeps filesystem and encoder behavior testable, actors serialize persistence, and value types carry parsed data across concurrency boundaries.

## Applied patterns

- **MVVM** keeps SwiftUI rendering separate from validation and workflow orchestration.
- **Repository** isolates versioned history persistence behind an actor.
- **Strategy + dependency injection** make Logic reading/writing, audio inspection/tagging, MP3 conversion, and GitHub release checks replaceable in tests.
- **State machine** represents update and long-running operation states explicitly instead of combining unrelated booleans.
- **Transactional write** builds Logic and audio outputs in temporary locations before publishing them.
- **Single source of truth** gives the main window and Settings one app-owned update service, preventing duplicate network checks and inconsistent results.
- **Adapter** confines GitHub’s JSON response and HTTP behavior to `GitHubReleaseClient`.

Swift value types, protocol-oriented design, and actors are preferred over class-only “pure OOP.” Classes are reserved for identity-bearing observable state and injected services where reference semantics are useful.

## Safety and performance invariants

1. A source Logic project is never modified.
2. A Logic copy is assembled in a temporary package; the source and any existing destination remain intact until validation succeeds.
3. Audio output is produced transactionally and is never published as a partial file.
4. History is encoded away from UI work and written atomically.
5. Replaceable operations have an identity; an obsolete result cannot overwrite a newer selection.
6. Long-running work and the LAME process cooperate with cancellation.
7. File handles and security-scoped resources close in `defer` blocks.
8. `ProjectData` scans use mapped `Data` and avoid a full `[UInt8]` duplicate.
9. User-impacting failures surface through accessible alerts instead of being silently ignored.
10. History has a versioned schema and a project + alternative + note identity.
11. Update and LAME archives are verified by SHA-256 before execution.
12. Unified logs never include user content, filenames, paths, project names, lyrics, prompts, artwork, or tag values.

## Concurrency and lifecycle

View models own cancelable task handles and capture themselves weakly in detached work. UI mutations return to the main actor. Operation identifiers reject stale completions. Temporary conversion files are removed in `defer`, and transient clipboard feedback tasks are canceled before replacement or view disappearance.

No source review can prove the absence of every runtime leak. Release validation therefore combines strict concurrency compilation and regression tests with recommended Instruments sessions (`Leaks`, `Allocations`, and `Time Profiler`) over repeated open/edit/convert/cancel/window-close cycles.

## Build validation

`BUILD.command`:

- compiles with complete strict-concurrency checking and concurrency warnings;
- executes core regression tests before building the app;
- validates English and French localization resources and `Info.plist`;
- signs the final bundle and verifies its signature;
- self-tests the bundled LAME binary;
- rejects LAME dependencies on Homebrew or `/usr/local`;
- optionally notarizes and staples Developer ID builds.

GitHub Actions runs the same lightweight pipeline on macOS and publishes checksummed app and source archives for tagged releases.
