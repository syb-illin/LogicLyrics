#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_ROOT="$SCRIPT_DIR/.build/light"
PRODUCT="$BUILD_ROOT/LogicLyrics.app"
DESTINATION="${LOGICLYRICS_DESTINATION:-$HOME/Downloads/LogicLyrics.app}"
ENTITLEMENTS="$SCRIPT_DIR/LogicLyrics/Resources/LogicLyrics.entitlements"
INFO_PLIST="$SCRIPT_DIR/LogicLyrics/Resources/Info.plist"
APP_ICON_SOURCE="$SCRIPT_DIR/LogicLyrics/Resources/AppIcon.png"
APP_ICON="$BUILD_ROOT/AppIcon.icns"
LAME_SHA256="ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e"

fail() {
    print "\nERROR: $1"
    if [[ "${LOGICLYRICS_NONINTERACTIVE:-0}" != "1" ]]; then
        /usr/bin/osascript -e "display alert \"Build Failed\" message \"$1\" as critical buttons {\"OK\"}" >/dev/null 2>&1 || true
        print "\nYou can close this window."
        read -k 1 "?Press any key to finish."
    fi
    exit 1
}

if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
    /usr/bin/xcode-select --install >/dev/null 2>&1 || true
    fail "Apple Command Line Tools are required. An installation window has opened. Complete the lightweight installation, then double-click BUILD.command again."
fi

SWIFTC="$(/usr/bin/xcrun --find swiftc)"
[[ -x "$SWIFTC" ]] || fail "The Swift compiler from Command Line Tools could not be found."
[[ -f "$INFO_PLIST" ]] || fail "Info.plist could not be found. Do not move BUILD.command out of the extracted folder."
[[ -f "$APP_ICON_SOURCE" ]] || fail "The AppIcon.png source could not be found."

ICON_WIDTH="$(/usr/bin/sips -g pixelWidth "$APP_ICON_SOURCE" 2>/dev/null | /usr/bin/awk '/pixelWidth/ {print $2}')"
ICON_HEIGHT="$(/usr/bin/sips -g pixelHeight "$APP_ICON_SOURCE" 2>/dev/null | /usr/bin/awk '/pixelHeight/ {print $2}')"
ICON_HAS_ALPHA="$(/usr/bin/sips -g hasAlpha "$APP_ICON_SOURCE" 2>/dev/null | /usr/bin/awk '/hasAlpha/ {print $2}')"
[[ "$ICON_WIDTH" == "$ICON_HEIGHT" && "$ICON_WIDTH" -ge 1024 ]] \
    || fail "AppIcon.png must be square and at least 1024 × 1024 pixels."
[[ "$ICON_HAS_ALPHA" == "no" ]] \
    || fail "AppIcon.png must be fully opaque so the macOS icon fills its complete mask."

SDK_PATH="$(/usr/bin/xcrun --sdk macosx --show-sdk-path 2>/dev/null)" \
    || fail "The macOS SDK from Command Line Tools could not be found. Run Software Update to update the Apple tools."
[[ -d "$SDK_PATH" ]] || fail "The macOS SDK path is invalid: $SDK_PATH"

ARCHITECTURE="$(/usr/bin/uname -m)"
case "$ARCHITECTURE" in
    arm64|x86_64) ;;
    *) fail "Unsupported Mac architecture: $ARCHITECTURE" ;;
esac
TARGET="$ARCHITECTURE-apple-macosx14.0"
CACHE_ROOT="$HOME/Library/Caches/com.local.LogicLyrics"
LAME_ROOT="$CACHE_ROOT/lame/3.100/$ARCHITECTURE"
LAME_BINARY="$LAME_ROOT/bin/lame"
LAME_ARCHIVE="$CACHE_ROOT/downloads/lame-3.100.tar.gz"

print "\nBuilding Logic Lyrics with Apple Command Line Tools…\n"

if [[ ! -x "$LAME_BINARY" && -x "$DESTINATION/Contents/Resources/lame" ]]; then
    if /usr/bin/lipo -archs "$DESTINATION/Contents/Resources/lame" 2>/dev/null | /usr/bin/grep -qw "$ARCHITECTURE"; then
        print "Reusing the installed MP3 engine…"
        /bin/mkdir -p "$LAME_ROOT/bin"
        /usr/bin/ditto "$DESTINATION/Contents/Resources/lame" "$LAME_BINARY"
        if [[ -f "$DESTINATION/Contents/Resources/LAME-LICENSE.txt" ]]; then
            /usr/bin/ditto "$DESTINATION/Contents/Resources/LAME-LICENSE.txt" "$LAME_ROOT/LAME-LICENSE.txt"
        fi
    fi
fi

if [[ ! -x "$LAME_BINARY" ]]; then
    print "Preparing the LAME MP3 engine (first build only)…"
    /bin/mkdir -p "$LAME_ROOT" "$CACHE_ROOT/downloads"
    if [[ -f "$LAME_ARCHIVE" ]]; then
        CACHED_SHA="$(/usr/bin/shasum -a 256 "$LAME_ARCHIVE" | /usr/bin/awk '{print $1}')"
        if [[ "$CACHED_SHA" != "$LAME_SHA256" ]]; then
            /bin/rm -f "$LAME_ARCHIVE"
        fi
    fi
    if [[ ! -f "$LAME_ARCHIVE" ]]; then
        /usr/bin/curl -L --fail --retry 3 \
            "https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz" \
            -o "$LAME_ARCHIVE" || fail "The official LAME source download failed. Check your Internet connection, then run BUILD.command again."
    else
        print "Found the LAME archive in the shared cache."
    fi
    ACTUAL_SHA="$(/usr/bin/shasum -a 256 "$LAME_ARCHIVE" | /usr/bin/awk '{print $1}')"
    [[ "$ACTUAL_SHA" == "$LAME_SHA256" ]] || fail "The LAME source security verification failed."
    LAME_SOURCE="$LAME_ROOT/lame-3.100"
    if [[ ! -d "$LAME_SOURCE" ]]; then
        /usr/bin/tar -xzf "$LAME_ARCHIVE" -C "$LAME_ROOT" || fail "The LAME archive could not be extracted."
    fi
    LAME_TRIPLE="$ARCHITECTURE-apple-darwin"
    [[ "$ARCHITECTURE" == "arm64" ]] && LAME_TRIPLE="aarch64-apple-darwin"
    (
        cd "$LAME_SOURCE"
        ./configure --build="$LAME_TRIPLE" --prefix="$LAME_ROOT" --disable-shared --enable-static --disable-gtktest --disable-decoder
        /usr/bin/make -j"$(/usr/sbin/sysctl -n hw.ncpu)"
        /usr/bin/make install
    ) || fail "The local LAME MP3 engine build failed."
fi
[[ -x "$LAME_BINARY" ]] || fail "The LAME MP3 engine was not produced."

[[ "$PRODUCT" == "$SCRIPT_DIR/.build/light/LogicLyrics.app" ]] || fail "Invalid build path."
/bin/rm -rf "$PRODUCT"
/bin/rm -rf "$BUILD_ROOT/AppIcon.iconset"
/bin/mkdir -p "$BUILD_ROOT/AppIcon.iconset"
for SPEC in "16:icon_16x16.png" "32:icon_16x16@2x.png" "32:icon_32x32.png" \
    "64:icon_32x32@2x.png" "128:icon_128x128.png" "256:icon_128x128@2x.png" \
    "256:icon_256x256.png" "512:icon_256x256@2x.png" "512:icon_512x512.png" \
    "1024:icon_512x512@2x.png"; do
    SIZE="${SPEC%%:*}"
    NAME="${SPEC#*:}"
    /usr/bin/sips -z "$SIZE" "$SIZE" "$APP_ICON_SOURCE" \
        --out "$BUILD_ROOT/AppIcon.iconset/$NAME" >/dev/null \
        || fail "An app icon size could not be generated."
done
/usr/bin/iconutil -c icns "$BUILD_ROOT/AppIcon.iconset" -o "$APP_ICON" \
    || fail "The macOS app icon could not be assembled."
/bin/mkdir -p "$PRODUCT/Contents/MacOS" "$PRODUCT/Contents/Resources"
/usr/bin/ditto "$INFO_PLIST" "$PRODUCT/Contents/Info.plist"
/usr/bin/ditto "$APP_ICON" "$PRODUCT/Contents/Resources/AppIcon.icns"
/usr/bin/ditto "$SCRIPT_DIR/LogicLyrics/Resources/UPDATE.command" "$PRODUCT/Contents/Resources/UPDATE.command"
/bin/chmod +x "$PRODUCT/Contents/Resources/UPDATE.command"
for LANGUAGE in en fr; do
    LOCALIZATION_SOURCE="$SCRIPT_DIR/LogicLyrics/Resources/$LANGUAGE.lproj/Localizable.strings"
    [[ -f "$LOCALIZATION_SOURCE" ]] || fail "The $LANGUAGE localization is missing."
    /bin/mkdir -p "$PRODUCT/Contents/Resources/$LANGUAGE.lproj"
    /usr/bin/ditto "$LOCALIZATION_SOURCE" "$PRODUCT/Contents/Resources/$LANGUAGE.lproj/Localizable.strings"
done
/usr/bin/ditto "$LAME_BINARY" "$PRODUCT/Contents/Resources/lame"
if [[ -f "$LAME_ROOT/lame-3.100/COPYING" ]]; then
    /usr/bin/ditto "$LAME_ROOT/lame-3.100/COPYING" "$PRODUCT/Contents/Resources/LAME-LICENSE.txt"
elif [[ -f "$LAME_ROOT/LAME-LICENSE.txt" ]]; then
    /usr/bin/ditto "$LAME_ROOT/LAME-LICENSE.txt" "$PRODUCT/Contents/Resources/LAME-LICENSE.txt"
fi
[[ -f "$PRODUCT/Contents/Resources/LAME-LICENSE.txt" ]] \
    || fail "The LAME MP3 engine license could not be found."

SOURCES=(
    "$SCRIPT_DIR/LogicLyrics/App/LogicLyricsApp.swift"
    "$SCRIPT_DIR/LogicLyrics/Model/ExtractedNote.swift"
    "$SCRIPT_DIR/LogicLyrics/Model/Localization.swift"
    "$SCRIPT_DIR/LogicLyrics/Model/LyricSection.swift"
    "$SCRIPT_DIR/LogicLyrics/Model/Observability.swift"
    "$SCRIPT_DIR/LogicLyrics/Model/OperationState.swift"
    "$SCRIPT_DIR/LogicLyrics/Model/SongHistoryEntry.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/LogicProjectReader.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/LogicProjectWriter.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/AudioMetadataWriter.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/AudioMetadataReader.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/MP3Converter.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/ServiceProtocols.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/UpdateService.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/ProjectLocator.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/HistoryArchiveService.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/HistoryStore.swift"
    "$SCRIPT_DIR/LogicLyrics/ViewModel/AudioMetadataViewModel.swift"
    "$SCRIPT_DIR/LogicLyrics/ViewModel/ProjectViewModel.swift"
    "$SCRIPT_DIR/LogicLyrics/ViewModel/SunoViewModel.swift"
    "$SCRIPT_DIR/LogicLyrics/Views/DesignSystem.swift"
    "$SCRIPT_DIR/LogicLyrics/Views/ContentView.swift"
    "$SCRIPT_DIR/LogicLyrics/Views/AudioMetadataView.swift"
    "$SCRIPT_DIR/LogicLyrics/Views/HistoryDetailView.swift"
    "$SCRIPT_DIR/LogicLyrics/Views/SettingsView.swift"
    "$SCRIPT_DIR/LogicLyrics/Views/SunoGeneratorView.swift"
)

CORE_TEST="$BUILD_ROOT/CoreRegressionTests"
"$SWIFTC" \
    -O \
    -strict-concurrency=complete \
    -warn-concurrency \
    -sdk "$SDK_PATH" \
    -target "$TARGET" \
    -framework AppKit \
    -framework SwiftUI \
    -o "$CORE_TEST" \
    "$SCRIPT_DIR/LogicLyrics/Model/ExtractedNote.swift" \
    "$SCRIPT_DIR/LogicLyrics/Model/Localization.swift" \
    "$SCRIPT_DIR/LogicLyrics/Model/LyricSection.swift" \
    "$SCRIPT_DIR/LogicLyrics/Model/Observability.swift" \
    "$SCRIPT_DIR/LogicLyrics/Model/OperationState.swift" \
    "$SCRIPT_DIR/LogicLyrics/Model/SongHistoryEntry.swift" \
    "$SCRIPT_DIR/LogicLyrics/Services/LogicProjectReader.swift" \
    "$SCRIPT_DIR/LogicLyrics/Services/LogicProjectWriter.swift" \
    "$SCRIPT_DIR/LogicLyrics/Services/AudioMetadataWriter.swift" \
    "$SCRIPT_DIR/LogicLyrics/Services/AudioMetadataReader.swift" \
    "$SCRIPT_DIR/LogicLyrics/Services/MP3Converter.swift" \
    "$SCRIPT_DIR/LogicLyrics/Services/ServiceProtocols.swift" \
    "$SCRIPT_DIR/LogicLyrics/Services/UpdateService.swift" \
    "$SCRIPT_DIR/LogicLyrics/Services/ProjectLocator.swift" \
    "$SCRIPT_DIR/LogicLyrics/Services/HistoryArchiveService.swift" \
    "$SCRIPT_DIR/LogicLyrics/Services/HistoryStore.swift" \
    "$SCRIPT_DIR/LogicLyrics/ViewModel/ProjectViewModel.swift" \
    "$SCRIPT_DIR/Tests/CoreRegressionTests.swift" \
    || fail "The regression tests could not be compiled."
"$CORE_TEST" || fail "A critical regression test failed."

"$SWIFTC" \
    -parse-as-library \
    -O \
    -strict-concurrency=complete \
    -warn-concurrency \
    -sdk "$SDK_PATH" \
    -target "$TARGET" \
    -framework SwiftUI \
    -framework AppKit \
    -framework Security \
    -o "$PRODUCT/Contents/MacOS/LogicLyrics" \
    "${SOURCES[@]}" || fail "The Swift compiler could not build the application. Make sure macOS and Command Line Tools are up to date."

[[ -x "$PRODUCT/Contents/MacOS/LogicLyrics" ]] || fail "The build completed without producing an executable."

if [[ -e "$DESTINATION" ]]; then
    TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
    /bin/mv "$DESTINATION" "$HOME/Downloads/LogicLyrics.previous-$TIMESTAMP.app" \
        || fail "The previous application could not be backed up."
fi

/usr/bin/ditto "$PRODUCT" "$DESTINATION" \
    || fail "The application could not be copied to the destination."

# This app has just been built locally from reviewed sources. Remove every
# download-origin extended attribute inherited from the source ZIP before
# signing, so the resulting code signature covers the final local bundle.
/usr/bin/xattr -cr "$DESTINATION" 2>/dev/null \
    || fail "The download attributes inherited from the ZIP could not be removed."

DETECTED_IDENTITY="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | /usr/bin/head -n 1)"
SIGN_IDENTITY="${LOGICLYRICS_SIGN_IDENTITY:-$DETECTED_IDENTITY}"
[[ -n "$SIGN_IDENTITY" ]] || SIGN_IDENTITY="-"
SIGN_ARGUMENTS=(--force --deep --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    SIGN_ARGUMENTS+=(--options runtime --timestamp)
fi
/usr/bin/codesign "${SIGN_ARGUMENTS[@]}" "$DESTINATION" \
    || fail "Application signing failed."

/usr/bin/codesign --verify --deep --strict "$DESTINATION" \
    || fail "Final application signature verification failed."

NOTARIZED=0
if [[ "$SIGN_IDENTITY" != "-" && -n "${LOGICLYRICS_NOTARY_PROFILE:-}" ]]; then
    NOTARY_ZIP="$BUILD_ROOT/LogicLyrics-notarization.zip"
    /usr/bin/ditto -c -k --keepParent "$DESTINATION" "$NOTARY_ZIP" \
        || fail "The notarization archive could not be created."
    /usr/bin/xcrun notarytool submit "$NOTARY_ZIP" \
        --keychain-profile "$LOGICLYRICS_NOTARY_PROFILE" --wait \
        || fail "Apple rejected or did not complete notarization."
    /usr/bin/xcrun stapler staple "$DESTINATION" \
        || fail "The notarization ticket could not be stapled."
    /usr/sbin/spctl --assess --type execute --verbose=2 "$DESTINATION" \
        || fail "Gatekeeper does not accept the notarized application."
    NOTARIZED=1
fi

/usr/bin/codesign --verify --deep --strict "$DESTINATION" \
    || fail "The signature is no longer valid after Gatekeeper preparation."

/usr/bin/plutil -lint "$DESTINATION/Contents/Info.plist" >/dev/null \
    || fail "The final application manifest is invalid."
for LANGUAGE in en fr; do
    /usr/bin/plutil -lint "$DESTINATION/Contents/Resources/$LANGUAGE.lproj/Localizable.strings" >/dev/null \
        || fail "The $LANGUAGE localization is invalid."
done
"$DESTINATION/Contents/Resources/lame" --version >/dev/null 2>&1 \
    || fail "The LAME MP3 engine self-test failed."
if /usr/bin/otool -L "$DESTINATION/Contents/Resources/lame" | /usr/bin/grep -Eq '/opt/homebrew|/usr/local'; then
    fail "The MP3 engine contains a forbidden external dependency."
fi

if [[ "${LOGICLYRICS_NONINTERACTIVE:-0}" != "1" ]]; then
    /usr/bin/open "$DESTINATION"
    /usr/bin/open -R "$DESTINATION"
    /usr/bin/osascript -e 'display notification "LogicLyrics.app is available in Downloads." with title "Build Complete"' >/dev/null 2>&1 || true
fi

print "\n✓ Application created: $DESTINATION"
if [[ "$NOTARIZED" == "1" ]]; then
    print "✓ Developer ID signature and Apple notarization verified."
elif [[ "$SIGN_IDENTITY" != "-" ]]; then
    print "✓ Developer ID signature verified. Configure LOGICLYRICS_NOTARY_PROFILE to notarize."
else
    print "✓ Local signature verified and download attributes removed."
    print "  Warning-free public distribution requires Developer ID and Apple notarization."
fi
print "✓ Shared LAME cache: $LAME_BINARY"
print "✓ Manifest and MP3 engine self-tests passed."
if [[ "${LOGICLYRICS_NONINTERACTIVE:-0}" != "1" ]]; then
    print "✓ The Downloads window is open."
    print "\nYou can close this window."
fi
