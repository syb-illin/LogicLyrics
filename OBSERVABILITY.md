# Observability

Logic Lyrics uses Apple Unified Logging through `OSLog`. There is no third-party analytics or crash-reporting SDK and no telemetry leaves the Mac.

## Remote telemetry

Remote telemetry is intentionally not implemented. Adding it responsibly requires a declared HTTPS endpoint, an explicit opt-in that defaults to off, a documented event schema, retention and deletion rules, and a published privacy policy. Lyrics, prompts, filenames, paths, project names, artist metadata, artwork, and stable user identifiers remain prohibited even if an opt-in backend is added later.

## Log model

Subsystem: `com.local.LogicLyrics`

Categories:

- `lifecycle`: launch and privacy-safe diagnostic export
- `projects`: Logic analysis, export, transactional copy, cancellation, duration, and failure class
- `audio`: inspection, metadata writes, WAV-to-MP3 conversion, cancellation, duration, and failure class
- `history`: repository initialization, load/save counts, duration, and persistence failures
- `updates`: update checks, remote version, updater launch, cancellation, and failure class

Durations are emitted as integer milliseconds. Counts and public format identifiers may be emitted where useful. Error logs include only the Swift error type, not the user-facing error message, because descriptions can contain filenames or paths.

## Privacy boundary

Logs must never contain:

- lyrics or generated prompts;
- project, track, album, artist, or filename values;
- filesystem paths or URLs;
- artwork or metadata payloads;
- history content or stable per-user identifiers.

The in-app **Diagnostics > Copy System Diagnostics** command follows the same boundary. It copies the app version/build, macOS version, architecture, selected app localization, current locale, and processor count.

## Inspecting logs

Use Console.app and filter by subsystem `com.local.LogicLyrics`, or stream from Terminal:

```sh
log stream --predicate 'subsystem == "com.local.LogicLyrics"' --level info
```

For a bounded support capture:

```sh
log show --last 15m --predicate 'subsystem == "com.local.LogicLyrics"' --info
```

Use Instruments Time Profiler, Allocations, and Leaks for performance investigations. Logs provide operational context; Instruments remains the source of truth for CPU and memory behavior.
