#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_ROOT="$HOME/Library/Caches/com.local.LogicLyrics/update"
ARCHIVE="$CACHE_ROOT/LogicLyrics-macOS-source.zip"
CHECKSUM="$ARCHIVE.sha256"
STAGING="$CACHE_ROOT/staging"
RELEASE_URL="https://github.com/syb-illin/LogicLyrics/releases/latest/download/LogicLyrics-macOS-source.zip"
TARGET_FILE="$SCRIPT_DIR/target-path.txt"

fail() {
    /usr/bin/osascript -e "display alert \"Update Failed\" message \"$1\" as critical buttons {\"OK\"}" >/dev/null 2>&1 || true
    print "\nERROR: $1"
    read -k 1 "?Press any key to finish."
    exit 1
}

/bin/mkdir -p "$CACHE_ROOT"
[[ -f "$TARGET_FILE" ]] || fail "The application destination is missing. Start the update again from Logic Lyrics."
TARGET_APPLICATION="$(<"$TARGET_FILE")"
[[ -n "$TARGET_APPLICATION" && "$TARGET_APPLICATION" == /* && "$TARGET_APPLICATION" == *.app ]] \
    || fail "The application destination is invalid."
[[ -d "$TARGET_APPLICATION" ]] || fail "The application to update could not be found."
[[ -w "$(dirname "$TARGET_APPLICATION")" ]] \
    || fail "The application folder is not writable by this user."
print "\nFinding and downloading the latest version of Logic Lyrics…\n"
/usr/bin/curl -L --fail --retry 3 "$RELEASE_URL" -o "$ARCHIVE" \
    || fail "The GitHub release could not be downloaded."
/usr/bin/curl -L --fail --retry 3 "$RELEASE_URL.sha256" -o "$CHECKSUM" \
    || fail "The release checksum is missing."

EXPECTED="$(/usr/bin/awk '{print $1}' "$CHECKSUM")"
ACTUAL="$(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print $1}')"
[[ -n "$EXPECTED" && "$EXPECTED" == "$ACTUAL" ]] \
    || fail "The update security verification failed."
if /usr/bin/unzip -Z1 "$ARCHIVE" | /usr/bin/grep -Eq '(^/|(^|/)\.\.(/|$))'; then
    fail "The archive contains an unsafe path."
fi

[[ "$STAGING" == "$CACHE_ROOT/staging" ]] || fail "Invalid working path."
/bin/rm -rf "$STAGING"
/bin/mkdir -p "$STAGING"
/usr/bin/ditto -x -k "$ARCHIVE" "$STAGING" || fail "The update archive is invalid."

BUILD_SCRIPT="$(/usr/bin/find "$STAGING" -maxdepth 3 -name BUILD.command -type f | /usr/bin/head -n 1)"
[[ -n "$BUILD_SCRIPT" && -f "$BUILD_SCRIPT" ]] || fail "BUILD.command is missing from the release."
/bin/chmod +x "$BUILD_SCRIPT"

# The updater is now independent from the running bundle, so the old process
# can be closed before its bundle is moved and replaced transactionally.
/usr/bin/osascript -e 'tell application id "com.local.LogicLyrics" to quit' >/dev/null 2>&1 || true
/bin/sleep 1
LOGICLYRICS_DESTINATION="$TARGET_APPLICATION" exec "$BUILD_SCRIPT"
