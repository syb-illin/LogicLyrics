# Observability

Logic Lyrics uses Apple Unified Logging through `OSLog`. There is no third-party analytics or crash SDK and no application telemetry leaves the Mac.

GitHub separately provides repository and release statistics. Those distribution metrics are generated within GitHub and cannot report app launches, active installations, feature usage, project contents or device identifiers.

## Log model

Subsystem: `com.local.LogicLyrics`

- `lifecycle`: launch and diagnostic-copy events
- `ui`: picker lifecycle and clipboard actions
- `projects`: Logic analysis start, cancellation, duration, note count and failure class
- `history`: repository initialization, load/save duration, entry counts and failure class
- `updates`: check trigger, duration, remote version, cancellation and updater launch
- `diagnostics`: bounded diagnostic-log collection failures

Dynamic values use explicit OSLog privacy annotations. Error events include only the Swift error type because descriptions may expose paths.

## Privacy boundary

Logs must never contain lyrics, project names, filenames, paths, URLs, bookmarks, prompts or stable per-user identifiers.

**Diagnostics → Copy System Diagnostics** includes app/system configuration and up to 200 privacy-safe Logic Lyrics events from the last 30 minutes. It does not query another process and does not transmit the result.

## Inspecting logs

```sh
log stream --predicate 'subsystem == "com.local.LogicLyrics"' --level info
```

For a bounded support capture:

```sh
log show --last 15m --predicate 'subsystem == "com.local.LogicLyrics"' --info
```

Use Instruments Time Profiler, Allocations and Leaks for CPU and memory investigations. Logs provide operational context; Instruments remains the runtime source of truth.
