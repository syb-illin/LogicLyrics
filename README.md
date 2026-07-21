# Logic Lyrics

Logic Lyrics is a native macOS app that reads lyrics from Logic Pro Project Notes, prepares voice-faithful Suno prompts, and manages metadata for Suno MP3/WAV exports.

Current version: **2.2.2 (build 27)**. Every shipped build receives a new build number.

## Features

- Opens `.logicx` packages and extracts embedded RTF Project Notes.
- Detects BPM and musical key from the selected Logic alternative.
- Keeps lyrics editable and recognizes Suno section markers such as `[Verse 1]`, `[Chorus]`, and `[Outro]`.
- Copies all lyrics or individual sections to the clipboard.
- Creates prompts with separate **Styles**, **Styles to Exclude**, and **Lyrics** blocks for ChatGPT or Gemini, without an API key.
- Places BPM and key at the beginning of the Suno Styles instructions.
- Locks the requested baritone identity to chest voice, natural grain and formants, with no falsetto, high notes, screaming, singer replacement, or unrealistic vocal acrobatics.
- Allows backing vocals and provides an explicit option for female backing vocals without replacing the lead.
- Stores a local history of loaded songs, edited lyrics, prompts, BPM, key, artist reference, and vocal settings.
- Reads and writes MP3/WAV metadata in a new file while preserving the original.
- Displays codec, sample rate, bit depth/bitrate, channel layout, duration, and embedded artwork.
- Uses a tokenized output filename template. The default is `{track} {group} - {title} {year}`; supported tokens are `{track}`, `{group}`, `{title}`, `{album}`, `{year}`, and `{bpm}`.
- Converts WAV to MP3 with locally built LAME 3.100 and configurable CBR/VBR and sample-rate settings.

The audio metadata screen defaults to artist `wake up fall` and the current year. Lyrics are excluded from tags by default, and the musical key is never written to audio metadata.

## Install or build

The GitHub Release contains a ready-built `LogicLyrics.app.zip`. The public build is ad-hoc signed unless the release workflow is configured with an Apple Developer ID and notarization credentials, so Gatekeeper may still request confirmation on another Mac.

For a local trusted build, double-click `BUILD.command`. It uses Apple Command Line Tools only; the full Xcode application and Homebrew are not required. The script:

1. validates the macOS SDK and architecture;
2. downloads the official LAME source once and verifies its SHA-256 checksum;
3. runs the regression suite and compiles with strict Swift concurrency checks;
4. signs and verifies the app;
5. places `LogicLyrics.app` in Downloads.

LAME is cached at `~/Library/Caches/com.local.LogicLyrics` and reused by future builds and updates. If a Developer ID Application identity exists in Keychain, the script detects it automatically. Set `LOGICLYRICS_NOTARY_PROFILE` to a configured `notarytool` profile to notarize and staple the result.

## Updates

The app can check GitHub Releases silently when it opens. This behavior is enabled by default and can be disabled in **Settings > Updates**. **Check Now** always remains available and shows an explicit checking, up-to-date, or available-version result. Installation requires **Install Update** followed by an **Install / Not Now** confirmation. When approved, the updater downloads the source archive and SHA-256 checksum, verifies both, rebuilds, and replaces the app at its current location. The shared LAME cache prevents repeated downloads and compilation.

A `vX.Y.Z` tag triggers the macOS workflow. Each release publishes:

- `LogicLyrics.app.zip` and its SHA-256 checksum;
- `LogicLyrics-macOS-source.zip` and its SHA-256 checksum.

## Logic project safety

Reading is non-destructive. Edited lyrics affect the local history, exports, prompts, and optional audio tags without changing the original `.logicx` package.

The experimental **Logic Copy** action works only on a duplicate. It locates a recognized terminal Notes record, updates its redundant lengths when required, reads the new copy back, and discards the temporary result if validation fails. If no lyrics exist, the app exposes an editable draft and attempts insertion only when the recognized empty Notes structure is present. Always open the resulting copy in Logic Pro to confirm compatibility.

## Languages, accessibility, and diagnostics

English is the source language. A complete French localization is bundled, and macOS selects the appropriate app language. Persisted settings use language-neutral identifiers so changing language does not reset MP3 choices.

The interface supports VoiceOver semantics, keyboard alternatives, Reduce Motion, Reduce Transparency, scalable labels, and state communication that does not rely on color alone. See [ACCESSIBILITY.md](ACCESSIBILITY.md).

Privacy-safe structured logs use the macOS Unified Logging system. The **Diagnostics > Copy System Diagnostics** command copies only app/system configuration and never lyrics, prompts, project names, file paths, or audio metadata. See [OBSERVABILITY.md](OBSERVABILITY.md).

## GitHub statistics

The repository includes a privacy-safe GitHub statistics dashboard. A scheduled GitHub Action archives release downloads and public repository metrics every day, preserving history beyond GitHub's rolling 14-day Traffic window. When the optional `TRAFFIC_TOKEN` repository secret is configured with read-only **Administration** access, it also archives views, unique visitors, clones, unique cloners, top referrers, and popular repository pages.

The generated website is stored on the dedicated `github-stats` branch and deployed through GitHub Pages. It measures the GitHub repository only: Logic Lyrics never sends launches, feature usage, lyrics, audio, file names, paths, prompts, or personal identifiers.

One-time setup:

1. In **Settings > Pages**, select **GitHub Actions** as the Pages source.
2. Create a fine-grained token limited to this repository with **Administration: Read-only**.
3. Add it under **Settings > Secrets and variables > Actions** as `TRAFFIC_TOKEN`.
4. Run **Actions > GitHub statistics dashboard > Run workflow**.

Without `TRAFFIC_TOKEN`, release downloads, stars, forks, watchers, issue/PR counts, and per-release history still work; the dashboard visibly marks GitHub Traffic data as unavailable instead of failing silently.

## Requirements and compatibility

- macOS 14 or later
- Apple Command Line Tools for local builds
- Validated sample: Logic Pro 12.2 (build 6644), RTF Project Notes

Open `LogicLyrics.xcodeproj` in Xcode 16 or later for IDE development. The production and safety invariants are documented in [ARCHITECTURE.md](ARCHITECTURE.md).
