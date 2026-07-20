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
    /usr/bin/osascript -e "display alert \"Compilation impossible\" message \"$1\" as critical buttons {\"OK\"}" >/dev/null 2>&1 || true
    print "\nERREUR : $1"
    if [[ "${LOGICLYRICS_NONINTERACTIVE:-0}" != "1" ]]; then
        print "\nTu peux fermer cette fenêtre."
        read -k 1 "?Appuie sur une touche pour terminer."
    fi
    exit 1
}

if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
    /usr/bin/xcode-select --install >/dev/null 2>&1 || true
    fail "Les Apple Command Line Tools sont nécessaires. Une fenêtre d’installation vient de s’ouvrir. Termine l’installation légère, puis redouble-clique sur BUILD.command."
fi

SWIFTC="$(/usr/bin/xcrun --find swiftc)"
[[ -x "$SWIFTC" ]] || fail "Le compilateur Swift des Command Line Tools est introuvable."
[[ -f "$INFO_PLIST" ]] || fail "Info.plist est introuvable. Ne déplace pas BUILD.command hors du dossier décompressé."
[[ -f "$APP_ICON_SOURCE" ]] || fail "La source transparente AppIcon.png est introuvable."

SDK_PATH="$(/usr/bin/xcrun --sdk macosx --show-sdk-path 2>/dev/null)" \
    || fail "Le SDK macOS des Command Line Tools est introuvable. Lance Mise à jour de logiciels pour actualiser les outils Apple."
[[ -d "$SDK_PATH" ]] || fail "Le chemin du SDK macOS est invalide : $SDK_PATH"

ARCHITECTURE="$(/usr/bin/uname -m)"
case "$ARCHITECTURE" in
    arm64|x86_64) ;;
    *) fail "Architecture Mac non reconnue : $ARCHITECTURE" ;;
esac
TARGET="$ARCHITECTURE-apple-macosx14.0"
CACHE_ROOT="$HOME/Library/Caches/com.local.LogicLyrics"
LAME_ROOT="$CACHE_ROOT/lame/3.100/$ARCHITECTURE"
LAME_BINARY="$LAME_ROOT/bin/lame"
LAME_ARCHIVE="$CACHE_ROOT/downloads/lame-3.100.tar.gz"

print "\nCompilation légère de Logic Lyrics avec Apple Command Line Tools…\n"

if [[ ! -x "$LAME_BINARY" && -x "$DESTINATION/Contents/Resources/lame" ]]; then
    if /usr/bin/lipo -archs "$DESTINATION/Contents/Resources/lame" 2>/dev/null | /usr/bin/grep -qw "$ARCHITECTURE"; then
        print "Réutilisation du moteur MP3 déjà installé…"
        /bin/mkdir -p "$LAME_ROOT/bin"
        /usr/bin/ditto "$DESTINATION/Contents/Resources/lame" "$LAME_BINARY"
        if [[ -f "$DESTINATION/Contents/Resources/LAME-LICENSE.txt" ]]; then
            /usr/bin/ditto "$DESTINATION/Contents/Resources/LAME-LICENSE.txt" "$LAME_ROOT/LAME-LICENSE.txt"
        fi
    fi
fi

if [[ ! -x "$LAME_BINARY" ]]; then
    print "Préparation du moteur MP3 LAME (première compilation uniquement)…"
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
            -o "$LAME_ARCHIVE" || fail "Le téléchargement de la source officielle LAME a échoué. Vérifie la connexion Internet puis relance BUILD.command."
    else
        print "Archive LAME trouvée dans le cache partagé."
    fi
    ACTUAL_SHA="$(/usr/bin/shasum -a 256 "$LAME_ARCHIVE" | /usr/bin/awk '{print $1}')"
    [[ "$ACTUAL_SHA" == "$LAME_SHA256" ]] || fail "La vérification de sécurité de la source LAME a échoué."
    LAME_SOURCE="$LAME_ROOT/lame-3.100"
    if [[ ! -d "$LAME_SOURCE" ]]; then
        /usr/bin/tar -xzf "$LAME_ARCHIVE" -C "$LAME_ROOT" || fail "L’archive LAME n’a pas pu être extraite."
    fi
    LAME_TRIPLE="$ARCHITECTURE-apple-darwin"
    [[ "$ARCHITECTURE" == "arm64" ]] && LAME_TRIPLE="aarch64-apple-darwin"
    (
        cd "$LAME_SOURCE"
        ./configure --build="$LAME_TRIPLE" --prefix="$LAME_ROOT" --disable-shared --enable-static --disable-gtktest --disable-decoder
        /usr/bin/make -j"$(/usr/sbin/sysctl -n hw.ncpu)"
        /usr/bin/make install
    ) || fail "La compilation locale du moteur MP3 LAME a échoué."
fi
[[ -x "$LAME_BINARY" ]] || fail "Le moteur MP3 LAME n’a pas été produit."

[[ "$PRODUCT" == "$SCRIPT_DIR/.build/light/LogicLyrics.app" ]] || fail "Chemin de build invalide."
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
        || fail "Une taille de l’icône n’a pas pu être générée."
done
/usr/bin/iconutil -c icns "$BUILD_ROOT/AppIcon.iconset" -o "$APP_ICON" \
    || fail "L’icône macOS n’a pas pu être assemblée."
/bin/mkdir -p "$PRODUCT/Contents/MacOS" "$PRODUCT/Contents/Resources"
/usr/bin/ditto "$INFO_PLIST" "$PRODUCT/Contents/Info.plist"
/usr/bin/ditto "$APP_ICON" "$PRODUCT/Contents/Resources/AppIcon.icns"
/usr/bin/ditto "$SCRIPT_DIR/LogicLyrics/Resources/UPDATE.command" "$PRODUCT/Contents/Resources/UPDATE.command"
/bin/chmod +x "$PRODUCT/Contents/Resources/UPDATE.command"
/usr/bin/ditto "$LAME_BINARY" "$PRODUCT/Contents/Resources/lame"
if [[ -f "$LAME_ROOT/lame-3.100/COPYING" ]]; then
    /usr/bin/ditto "$LAME_ROOT/lame-3.100/COPYING" "$PRODUCT/Contents/Resources/LAME-LICENSE.txt"
elif [[ -f "$LAME_ROOT/LAME-LICENSE.txt" ]]; then
    /usr/bin/ditto "$LAME_ROOT/LAME-LICENSE.txt" "$PRODUCT/Contents/Resources/LAME-LICENSE.txt"
fi
[[ -f "$PRODUCT/Contents/Resources/LAME-LICENSE.txt" ]] \
    || fail "La licence du moteur MP3 LAME est introuvable."

SOURCES=(
    "$SCRIPT_DIR/LogicLyrics/App/LogicLyricsApp.swift"
    "$SCRIPT_DIR/LogicLyrics/Model/ExtractedNote.swift"
    "$SCRIPT_DIR/LogicLyrics/Model/LyricSection.swift"
    "$SCRIPT_DIR/LogicLyrics/Model/OperationState.swift"
    "$SCRIPT_DIR/LogicLyrics/Model/SongHistoryEntry.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/LogicProjectReader.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/LogicProjectWriter.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/AudioMetadataWriter.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/AudioMetadataReader.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/MP3Converter.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/ServiceProtocols.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/UpdateService.swift"
    "$SCRIPT_DIR/LogicLyrics/Services/HistoryStore.swift"
    "$SCRIPT_DIR/LogicLyrics/ViewModel/AudioMetadataViewModel.swift"
    "$SCRIPT_DIR/LogicLyrics/ViewModel/ProjectViewModel.swift"
    "$SCRIPT_DIR/LogicLyrics/ViewModel/SunoViewModel.swift"
    "$SCRIPT_DIR/LogicLyrics/Views/DesignSystem.swift"
    "$SCRIPT_DIR/LogicLyrics/Views/ContentView.swift"
    "$SCRIPT_DIR/LogicLyrics/Views/AudioMetadataView.swift"
    "$SCRIPT_DIR/LogicLyrics/Views/HistoryDetailView.swift"
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
    -o "$CORE_TEST" \
    "$SCRIPT_DIR/LogicLyrics/Model/ExtractedNote.swift" \
    "$SCRIPT_DIR/LogicLyrics/Model/LyricSection.swift" \
    "$SCRIPT_DIR/LogicLyrics/Model/SongHistoryEntry.swift" \
    "$SCRIPT_DIR/LogicLyrics/Services/LogicProjectReader.swift" \
    "$SCRIPT_DIR/LogicLyrics/Services/LogicProjectWriter.swift" \
    "$SCRIPT_DIR/LogicLyrics/Services/AudioMetadataWriter.swift" \
    "$SCRIPT_DIR/LogicLyrics/Services/AudioMetadataReader.swift" \
    "$SCRIPT_DIR/Tests/CoreRegressionTests.swift" \
    || fail "Les tests de régression n’ont pas pu être compilés."
"$CORE_TEST" || fail "Un test de régression critique a échoué."

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
    "${SOURCES[@]}" || fail "Le compilateur Swift n’a pas réussi à construire l’application. Vérifie que macOS et les Command Line Tools sont à jour."

[[ -x "$PRODUCT/Contents/MacOS/LogicLyrics" ]] || fail "La compilation s’est terminée sans produire l’exécutable."

if [[ -e "$DESTINATION" ]]; then
    TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
    /bin/mv "$DESTINATION" "$HOME/Downloads/LogicLyrics.previous-$TIMESTAMP.app" \
        || fail "L’ancienne application n’a pas pu être sauvegardée."
fi

/usr/bin/ditto "$PRODUCT" "$DESTINATION" \
    || fail "L’application n’a pas pu être copiée dans Téléchargements."

# This app has just been built locally from reviewed sources. Remove every
# download-origin extended attribute inherited from the source ZIP before
# signing, so the resulting code signature covers the final local bundle.
/usr/bin/xattr -cr "$DESTINATION" 2>/dev/null \
    || fail "Les attributs de téléchargement hérités du ZIP n’ont pas pu être retirés."

DETECTED_IDENTITY="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | /usr/bin/head -n 1)"
SIGN_IDENTITY="${LOGICLYRICS_SIGN_IDENTITY:-$DETECTED_IDENTITY}"
[[ -n "$SIGN_IDENTITY" ]] || SIGN_IDENTITY="-"
SIGN_ARGUMENTS=(--force --deep --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    SIGN_ARGUMENTS+=(--options runtime --timestamp)
fi
/usr/bin/codesign "${SIGN_ARGUMENTS[@]}" "$DESTINATION" \
    || fail "La signature de l’application a échoué."

/usr/bin/codesign --verify --deep --strict "$DESTINATION" \
    || fail "La vérification finale de l’application a échoué."

NOTARIZED=0
if [[ "$SIGN_IDENTITY" != "-" && -n "${LOGICLYRICS_NOTARY_PROFILE:-}" ]]; then
    NOTARY_ZIP="$BUILD_ROOT/LogicLyrics-notarization.zip"
    /usr/bin/ditto -c -k --keepParent "$DESTINATION" "$NOTARY_ZIP" \
        || fail "L’archive de notarisation n’a pas pu être créée."
    /usr/bin/xcrun notarytool submit "$NOTARY_ZIP" \
        --keychain-profile "$LOGICLYRICS_NOTARY_PROFILE" --wait \
        || fail "Apple a refusé ou n’a pas terminé la notarisation."
    /usr/bin/xcrun stapler staple "$DESTINATION" \
        || fail "Le ticket de notarisation n’a pas pu être attaché."
    /usr/sbin/spctl --assess --type execute --verbose=2 "$DESTINATION" \
        || fail "Gatekeeper n’accepte pas l’application notarialisée."
    NOTARIZED=1
fi

/usr/bin/codesign --verify --deep --strict "$DESTINATION" \
    || fail "La signature n’est plus valide après la préparation Gatekeeper."

/usr/bin/plutil -lint "$DESTINATION/Contents/Info.plist" >/dev/null \
    || fail "Le manifeste final de l’application est invalide."
"$DESTINATION/Contents/Resources/lame" --version >/dev/null 2>&1 \
    || fail "L’auto-test du moteur MP3 LAME a échoué."
if /usr/bin/otool -L "$DESTINATION/Contents/Resources/lame" | /usr/bin/grep -Eq '/opt/homebrew|/usr/local'; then
    fail "Le moteur MP3 contient une dépendance externe interdite."
fi

if [[ "${LOGICLYRICS_NONINTERACTIVE:-0}" != "1" ]]; then
    /usr/bin/open "$DESTINATION"
    /usr/bin/open -R "$DESTINATION"
    /usr/bin/osascript -e 'display notification "LogicLyrics.app est disponible dans Téléchargements." with title "Compilation terminée"' >/dev/null 2>&1 || true
fi

print "\n✓ Application créée : $DESTINATION"
if [[ "$NOTARIZED" == "1" ]]; then
    print "✓ Signature Developer ID et notarisation Apple vérifiées."
elif [[ "$SIGN_IDENTITY" != "-" ]]; then
    print "✓ Signature Developer ID vérifiée. Configure LOGICLYRICS_NOTARY_PROFILE pour notariser."
else
    print "✓ Signature locale vérifiée et attributs de téléchargement retirés."
    print "  Une distribution publique sans avertissement exige Developer ID + notarisation Apple."
fi
print "✓ Cache LAME partagé : $LAME_BINARY"
print "✓ Auto-tests du manifeste et du moteur MP3 réussis."
if [[ "${LOGICLYRICS_NONINTERACTIVE:-0}" != "1" ]]; then
    print "✓ La fenêtre Téléchargements est ouverte."
    print "\nTu peux fermer cette fenêtre."
fi
