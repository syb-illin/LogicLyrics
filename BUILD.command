#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/Tools/InstallTransaction.zsh"
BUILD_ROOT="$SCRIPT_DIR/.build/light"
PRODUCT="$BUILD_ROOT/LogicLyrics.app"
DESTINATION="${LOGICLYRICS_DESTINATION:-$HOME/Downloads/LogicLyrics.app}"
ENTITLEMENTS="$SCRIPT_DIR/LogicLyrics/Resources/LogicLyrics.entitlements"
INFO_PLIST="$SCRIPT_DIR/LogicLyrics/Resources/Info.plist"
APP_ICON_SOURCE="$SCRIPT_DIR/LogicLyrics/Resources/AppIcon.png"
APP_ICON="$BUILD_ROOT/AppIcon.icns"
rollback_install() {
    rollback_install_transaction "$DESTINATION"
}

fail() {
    rollback_install
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

print "\nBuilding Logic Lyrics with Apple Command Line Tools…\n"

/bin/zsh "$SCRIPT_DIR/Tools/TestInstallTransaction.zsh" \
    || fail "The transactional installer regression test failed."

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
    LOCALIZATION_KEYS="$BUILD_ROOT/localization-$LANGUAGE.keys"
    LOCALIZATION_DUPLICATES="$BUILD_ROOT/localization-$LANGUAGE-duplicates.txt"
    LC_ALL=C /usr/bin/sed -E -n 's/^"(([^"\\]|\\.)*)"[[:space:]]*=.*/\1/p' "$LOCALIZATION_SOURCE" \
        | /usr/bin/sort > "$LOCALIZATION_KEYS"
    /usr/bin/uniq -d "$LOCALIZATION_KEYS" > "$LOCALIZATION_DUPLICATES"
    [[ ! -s "$LOCALIZATION_DUPLICATES" ]] \
        || fail "The $LANGUAGE localization contains duplicate keys."
done
if ! /usr/bin/cmp -s "$BUILD_ROOT/localization-en.keys" "$BUILD_ROOT/localization-fr.keys"; then
    print "\nEnglish and French localization keys are not aligned:"
    /usr/bin/diff -u "$BUILD_ROOT/localization-en.keys" "$BUILD_ROOT/localization-fr.keys" || true
    fail "Every user-facing localization key must exist in both English and French."
fi
/usr/bin/python3 "$SCRIPT_DIR/Tools/check_localizations.py" \
    "$SCRIPT_DIR/LogicLyrics" \
    "$SCRIPT_DIR/LogicLyrics/Resources/en.lproj/Localizable.strings" \
    "$SCRIPT_DIR/LogicLyrics/Resources/fr.lproj/Localizable.strings" \
    || fail "App-wide English/French localization validation failed."
SOURCES=(
    "$SCRIPT_DIR/LogicLyrics/App/LogicLyricsApp.swift"
    "$SCRIPT_DIR/LogicLyrics/App/LogicProjectCommands.swift"
    "$SCRIPT_DIR/LogicLyrics/Model/ExtractedNote.swift"
    "$SCRIPT_DIR/LogicLyrics/Model/HistorySearch.swift"
    "$SCRIPT_DIR/LogicLyrics/Model/Localization.swift"
    "$SCRIPT_DIR/LogicLyrics/Model/LyricSection.swift"
    "$SCRIPT_DIR/LogicLyrics/Model/Observability.swift"
    "$SCRIPT_DIR/LogicLyrics/Model/OperationState.swift"
    "$SCRIPT_DIR/LogicLyrics/Model/SongHistoryEntry.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/LogicProjectReader.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/ServiceProtocols.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/UpdateService.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/UpdateInstaller.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/ProjectLocator.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/ProjectBookmarkManager.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/HistoryStore.swift"
    "$SCRIPT_DIR/LogicLyrics/ViewModel/ProjectViewModel.swift"
    "$SCRIPT_DIR/LogicLyrics/Views/DesignSystem.swift"
    "$SCRIPT_DIR/LogicLyrics/Views/ContentView.swift"
    "$SCRIPT_DIR/LogicLyrics/Views/LyricsReaderView.swift"
    "$SCRIPT_DIR/LogicLyrics/Views/RecentProjectsView.swift"
    "$SCRIPT_DIR/LogicLyrics/Views/SettingsView.swift"
)

# Keep the lightweight Command Line Tools build aligned with the application
# target. A missing Swift file must fail here with an actionable diff instead
# of surfacing later as an unrelated compiler error.
DECLARED_SOURCES="$BUILD_ROOT/declared-swift-sources.txt"
DISCOVERED_SOURCES="$BUILD_ROOT/discovered-swift-sources.txt"
printf '%s\n' "${SOURCES[@]}" | /usr/bin/sort > "$DECLARED_SOURCES"
/usr/bin/find "$SCRIPT_DIR/LogicLyrics" -type f -name '*.swift' -print \
    | /usr/bin/sort > "$DISCOVERED_SOURCES"
if ! /usr/bin/cmp -s "$DECLARED_SOURCES" "$DISCOVERED_SOURCES"; then
    print "\nBUILD.command Swift source manifest is out of date:"
    /usr/bin/diff -u "$DECLARED_SOURCES" "$DISCOVERED_SOURCES" || true
    fail "BUILD.command must declare every Swift source in LogicLyrics before compiling."
fi

CORE_TEST="$BUILD_ROOT/CoreRegressionTests"
CORE_TEST_FLAGS=(
    -O
    -strict-concurrency=complete
    -warn-concurrency
    -sdk "$SDK_PATH"
    -target "$TARGET"
    -framework AppKit
    -framework SwiftUI
)
if [[ "${LOGICLYRICS_CORE_COVERAGE:-0}" == "1" ]]; then
    CORE_TEST_FLAGS=(
        -Onone
        -profile-generate
        -profile-coverage-mapping
        -strict-concurrency=complete
        -warn-concurrency
        -sdk "$SDK_PATH"
        -target "$TARGET"
        -framework AppKit
        -framework SwiftUI
    )
fi
"$SWIFTC" \
    "${CORE_TEST_FLAGS[@]}" \
    -o "$CORE_TEST" \
    "$SCRIPT_DIR/LogicLyrics/Model/ExtractedNote.swift" \
    "$SCRIPT_DIR/LogicLyrics/Model/HistorySearch.swift" \
    "$SCRIPT_DIR/LogicLyrics/Model/Localization.swift" \
    "$SCRIPT_DIR/LogicLyrics/Model/LyricSection.swift" \
    "$SCRIPT_DIR/LogicLyrics/Model/Observability.swift" \
    "$SCRIPT_DIR/LogicLyrics/Model/OperationState.swift" \
    "$SCRIPT_DIR/LogicLyrics/Model/SongHistoryEntry.swift" \
    "$SCRIPT_DIR/LogicLyrics/Services/LogicProjectReader.swift" \
    "$SCRIPT_DIR/LogicLyrics/Services/ServiceProtocols.swift" \
    "$SCRIPT_DIR/LogicLyrics/Services/UpdateService.swift" \
    "$SCRIPT_DIR/LogicLyrics/Services/UpdateInstaller.swift" \
    "$SCRIPT_DIR/LogicLyrics/Services/ProjectLocator.swift" \
    "$SCRIPT_DIR/LogicLyrics/Services/ProjectBookmarkManager.swift" \
    "$SCRIPT_DIR/LogicLyrics/Services/HistoryStore.swift" \
    "$SCRIPT_DIR/LogicLyrics/ViewModel/ProjectViewModel.swift" \
    "$SCRIPT_DIR/Tests/CoreRegressionTests.swift" \
    || fail "The regression tests could not be compiled."
if [[ "${LOGICLYRICS_CORE_COVERAGE:-0}" == "1" ]]; then
    /bin/rm -f "$BUILD_ROOT"/core-*.profraw(N)
    LLVM_PROFILE_FILE="$BUILD_ROOT/core-%p.profraw" "$CORE_TEST" \
        || fail "A critical regression test failed."
    COVERAGE_PROFILES=("$BUILD_ROOT"/core-*.profraw(N))
    (( ${#COVERAGE_PROFILES} > 0 )) || fail "Core tests did not produce a coverage profile."
    COVERAGE_DATA="$BUILD_ROOT/CoreRegressionTests.profdata"
    COVERAGE_REPORT="$BUILD_ROOT/CoreCoverage.json"
    /usr/bin/xcrun llvm-profdata merge -sparse "${COVERAGE_PROFILES[@]}" -o "$COVERAGE_DATA" \
        || fail "Core coverage profiles could not be merged."
    /usr/bin/xcrun llvm-cov export "$CORE_TEST" -instr-profile="$COVERAGE_DATA" \
        > "$COVERAGE_REPORT" \
        || fail "Core coverage could not be exported."
    # Pure policies stay at literal 100%. Service thresholds include system
    # adapter and cancellation branches, are enforced independently, and can
    # only be raised as coverage grows—never hidden by one blended percentage.
    /usr/bin/python3 "$SCRIPT_DIR/Tools/check_swift_coverage.py" \
        "$COVERAGE_REPORT" \
        --minimum "${LOGICLYRICS_CORE_COVERAGE_MINIMUM:-100}" \
        LogicLyrics/Model/HistorySearch.swift \
        LogicLyrics/Model/LyricSection.swift \
        || fail "Pure policy coverage is below the required threshold."
    /usr/bin/python3 "$SCRIPT_DIR/Tools/check_swift_coverage.py" \
        "$COVERAGE_REPORT" --minimum "${LOGICLYRICS_SERVICE_COVERAGE_MINIMUM:-90}" \
        LogicLyrics/Services/LogicProjectReader.swift \
        LogicLyrics/Services/ProjectLocator.swift \
        LogicLyrics/Services/UpdateService.swift \
        || fail "Core service coverage is below the required threshold."
    /usr/bin/python3 "$SCRIPT_DIR/Tools/check_swift_coverage.py" \
        "$COVERAGE_REPORT" --minimum "${LOGICLYRICS_VIEW_MODEL_COVERAGE_MINIMUM:-85}" \
        LogicLyrics/ViewModel/ProjectViewModel.swift \
        || fail "View-model coverage is below the required threshold."
    /usr/bin/python3 "$SCRIPT_DIR/Tools/check_swift_coverage.py" \
        "$COVERAGE_REPORT" --minimum "${LOGICLYRICS_HISTORY_COVERAGE_MINIMUM:-75}" \
        LogicLyrics/Services/HistoryStore.swift \
        || fail "History coverage is below the required threshold."
else
    "$CORE_TEST" || fail "A critical regression test failed."
fi

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

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
TRANSACTION_BACKUP="$HOME/Downloads/LogicLyrics.previous-$TIMESTAMP.app"
transactional_install "$PRODUCT" "$DESTINATION" "$TRANSACTION_BACKUP" \
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

commit_install_transaction

# Bootstrap the production sandbox container before importing data from the old
# bundle identifier. History is staged for schema-5 merge by HistoryRepository;
# the original container is retained as a rollback source.
OLD_LIBRARY="$HOME/Library/Containers/com.local.LogicLyrics/Data/Library"
NEW_LIBRARY="$HOME/Library/Containers/com.sybillin.LogicLyrics/Data/Library"
NEW_CONTAINER="$HOME/Library/Containers/com.sybillin.LogicLyrics"
MIGRATION_MARKER="$NEW_LIBRARY/Application Support/LogicLyrics/.bundle-id-migration-complete"
OLD_HISTORY="$OLD_LIBRARY/Application Support/LogicLyrics/history.json"
if [[ -f "$OLD_HISTORY" && ! -f "$MIGRATION_MARKER" && "${LOGICLYRICS_NONINTERACTIVE:-0}" != "1" ]]; then
    if [[ ! -f "$NEW_CONTAINER/.com.apple.containermanagerd.metadata.plist" ]]; then
        /usr/bin/open -gj "$DESTINATION" 2>/dev/null || true
        for _ in {1..20}; do
            [[ -f "$NEW_CONTAINER/.com.apple.containermanagerd.metadata.plist" ]] && break
            /bin/sleep 0.2
        done
        /usr/bin/osascript -e 'tell application id "com.sybillin.LogicLyrics" to quit' >/dev/null 2>&1 || true
    fi
    if [[ -f "$NEW_CONTAINER/.com.apple.containermanagerd.metadata.plist" ]]; then
        /bin/mkdir -p "$NEW_LIBRARY/Application Support/LogicLyrics" "$NEW_LIBRARY/Preferences"
        /usr/bin/ditto "$OLD_HISTORY" "$NEW_LIBRARY/Application Support/LogicLyrics/history-legacy-bundle-import.json" \
            || fail "The previous history could not be staged for migration."
        OLD_PREFS="$OLD_LIBRARY/Preferences/com.local.LogicLyrics.plist"
        if [[ -f "$OLD_PREFS" ]]; then
            /usr/bin/ditto "$OLD_PREFS" "$NEW_LIBRARY/Preferences/com.sybillin.LogicLyrics.plist" \
                || fail "The previous preferences could not be migrated."
        fi
        /usr/bin/touch "$MIGRATION_MARKER"
    else
        print "Warning: the previous history remains safe but its new sandbox container could not be initialized."
    fi
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
print "✓ Source manifest and regression tests passed."
if [[ "${LOGICLYRICS_NONINTERACTIVE:-0}" != "1" ]]; then
    print "✓ The Downloads window is open."
    print "\nYou can close this window."
fi
