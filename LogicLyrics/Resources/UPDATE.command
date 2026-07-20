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
    /usr/bin/osascript -e "display alert \"Mise à jour impossible\" message \"$1\" as critical buttons {\"OK\"}" >/dev/null 2>&1 || true
    print "\nERREUR : $1"
    read -k 1 "?Appuie sur une touche pour terminer."
    exit 1
}

/bin/mkdir -p "$CACHE_ROOT"
[[ -f "$TARGET_FILE" ]] || fail "La destination de l’application est absente. Relance la mise à jour depuis Logic Lyrics."
TARGET_APPLICATION="$(<"$TARGET_FILE")"
[[ -n "$TARGET_APPLICATION" && "$TARGET_APPLICATION" == /* && "$TARGET_APPLICATION" == *.app ]] \
    || fail "La destination de l’application est invalide."
[[ -d "$TARGET_APPLICATION" ]] || fail "L’application à mettre à jour est introuvable."
[[ -w "$(dirname "$TARGET_APPLICATION")" ]] \
    || fail "Le dossier de l’application n’est pas modifiable par cet utilisateur."
print "\nRecherche et téléchargement de la dernière version de Logic Lyrics…\n"
/usr/bin/curl -L --fail --retry 3 "$RELEASE_URL" -o "$ARCHIVE" \
    || fail "La release GitHub n’a pas pu être téléchargée."
/usr/bin/curl -L --fail --retry 3 "$RELEASE_URL.sha256" -o "$CHECKSUM" \
    || fail "La somme de contrôle de la release est absente."

EXPECTED="$(/usr/bin/awk '{print $1}' "$CHECKSUM")"
ACTUAL="$(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print $1}')"
[[ -n "$EXPECTED" && "$EXPECTED" == "$ACTUAL" ]] \
    || fail "La vérification de sécurité de la mise à jour a échoué."
if /usr/bin/unzip -Z1 "$ARCHIVE" | /usr/bin/grep -Eq '(^/|(^|/)\.\.(/|$))'; then
    fail "L’archive contient un chemin non sécurisé."
fi

[[ "$STAGING" == "$CACHE_ROOT/staging" ]] || fail "Chemin de travail invalide."
/bin/rm -rf "$STAGING"
/bin/mkdir -p "$STAGING"
/usr/bin/ditto -x -k "$ARCHIVE" "$STAGING" || fail "L’archive de mise à jour est invalide."

BUILD_SCRIPT="$(/usr/bin/find "$STAGING" -maxdepth 3 -name BUILD.command -type f | /usr/bin/head -n 1)"
[[ -n "$BUILD_SCRIPT" && -f "$BUILD_SCRIPT" ]] || fail "BUILD.command est absent de la release."
/bin/chmod +x "$BUILD_SCRIPT"

# The updater is now independent from the running bundle, so the old process
# can be closed before its bundle is moved and replaced transactionally.
/usr/bin/osascript -e 'tell application id "com.local.LogicLyrics" to quit' >/dev/null 2>&1 || true
/bin/sleep 1
LOGICLYRICS_DESTINATION="$TARGET_APPLICATION" exec "$BUILD_SCRIPT"
