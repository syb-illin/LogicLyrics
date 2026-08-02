#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_ROOT="$HOME/Library/Caches/com.sybillin.LogicLyrics/update"
ARCHIVE="$CACHE_ROOT/LogicLyrics-macOS-source.zip"
CHECKSUM="$ARCHIVE.sha256"
STAGING="$CACHE_ROOT/staging"
TARGET_FILE="$SCRIPT_DIR/target-path.txt"
VERSION_FILE="$SCRIPT_DIR/expected-version.txt"
ARCHIVE_URL_FILE="$SCRIPT_DIR/archive-url.txt"
CHECKSUM_URL_FILE="$SCRIPT_DIR/checksum-url.txt"

fail() {
    /usr/bin/osascript -e "display alert \"Update Failed\" message \"$1\" as critical buttons {\"OK\"}" >/dev/null 2>&1 || true
    print "\nERROR: $1"
    read -k 1 "?Press any key to finish."
    exit 1
}

for REQUIRED in "$TARGET_FILE" "$VERSION_FILE" "$ARCHIVE_URL_FILE" "$CHECKSUM_URL_FILE"; do
    [[ -f "$REQUIRED" ]] || fail "The verified update plan is incomplete. Check for updates again."
done

TARGET_APPLICATION="$(<"$TARGET_FILE")"
EXPECTED_VERSION="$(<"$VERSION_FILE")"
ARCHIVE_URL="$(<"$ARCHIVE_URL_FILE")"
CHECKSUM_URL="$(<"$CHECKSUM_URL_FILE")"

[[ -n "$TARGET_APPLICATION" && "$TARGET_APPLICATION" == /* && "$TARGET_APPLICATION" == *.app ]] \
    || fail "The application destination is invalid."
[[ "$EXPECTED_VERSION" == <->.<->.<-> ]] || fail "The expected update version is invalid."
TRUSTED_PREFIX="https://github.com/syb-illin/LogicLyrics/releases/download/"
[[ "$ARCHIVE_URL" == "$TRUSTED_PREFIX"*"/LogicLyrics-macOS-source.zip" ]] \
    || fail "The update archive URL is not trusted."
[[ "$CHECKSUM_URL" == "$TRUSTED_PREFIX"*"/LogicLyrics-macOS-source.zip.sha256" ]] \
    || fail "The update checksum URL is not trusted."
[[ "${ARCHIVE_URL%/LogicLyrics-macOS-source.zip}" == "${CHECKSUM_URL%/LogicLyrics-macOS-source.zip.sha256}" ]] \
    || fail "The update files do not belong to the same release."
[[ -d "$TARGET_APPLICATION" ]] || fail "The application to update could not be found."
[[ -w "$(dirname "$TARGET_APPLICATION")" ]] \
    || fail "The application folder is not writable by this user."

/bin/mkdir -p "$CACHE_ROOT"
print "\nDownloading the verified Logic Lyrics $EXPECTED_VERSION update…\n"
/usr/bin/curl -L --fail --retry 3 "$ARCHIVE_URL" -o "$ARCHIVE" \
    || fail "The GitHub release could not be downloaded."
/usr/bin/curl -L --fail --retry 3 "$CHECKSUM_URL" -o "$CHECKSUM" \
    || fail "The release checksum is missing."

EXPECTED="$(/usr/bin/awk '{print $1}' "$CHECKSUM")"
ACTUAL="$(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print $1}')"
[[ "$EXPECTED" =~ '^[0-9a-fA-F]{64}$' && "$EXPECTED" == "$ACTUAL" ]] \
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
SOURCE_INFO="$(/usr/bin/find "$(dirname "$BUILD_SCRIPT")" -path '*/LogicLyrics/Resources/Info.plist' -type f | /usr/bin/head -n 1)"
[[ -f "$SOURCE_INFO" ]] || fail "The release manifest is missing."
SOURCE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_INFO" 2>/dev/null)"
[[ "$SOURCE_VERSION" == "$EXPECTED_VERSION" ]] \
    || fail "The downloaded release version does not match the update you approved."
/bin/chmod +x "$BUILD_SCRIPT"

/usr/bin/osascript -e 'tell application id "com.sybillin.LogicLyrics" to quit' >/dev/null 2>&1 || true
/usr/bin/osascript -e 'tell application id "com.local.LogicLyrics" to quit' >/dev/null 2>&1 || true
/bin/sleep 1
LOGICLYRICS_DESTINATION="$TARGET_APPLICATION" exec "$BUILD_SCRIPT"
