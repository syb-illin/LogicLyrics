#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/InstallTransaction.zsh"
ROOT="${TMPDIR:-/tmp}/logiclyrics-install-transaction-$$"
SOURCE="$ROOT/Source.app"
DESTINATION="$ROOT/LogicLyrics.app"
BACKUP="$ROOT/LogicLyrics.previous.app"
trap '/bin/rm -rf "$ROOT"' EXIT

/bin/mkdir -p "$SOURCE" "$DESTINATION"
print -n "new" > "$SOURCE/version"
print -n "old" > "$DESTINATION/version"

LOGICLYRICS_TEST_INSTALL_FAULT=after-backup
if transactional_install "$SOURCE" "$DESTINATION" "$BACKUP"; then
    print "Fault injection unexpectedly succeeded" >&2
    exit 1
fi
rollback_install_transaction "$DESTINATION"
[[ -f "$DESTINATION/version" && "$(<"$DESTINATION/version")" == "old" ]] \
    || { print "Rollback did not restore the previous app" >&2; exit 1; }

/bin/mkdir -p "$SOURCE"
print -n "new" > "$SOURCE/version"
unset LOGICLYRICS_TEST_INSTALL_FAULT
transactional_install "$SOURCE" "$DESTINATION" "$BACKUP"
[[ "$(<"$DESTINATION/version")" == "new" ]] \
    || { print "Committed app is not the new build" >&2; exit 1; }
[[ "$(<"$BACKUP/version")" == "old" ]] \
    || { print "Successful install did not preserve its backup" >&2; exit 1; }
commit_install_transaction
print "Install transaction tests: OK"
