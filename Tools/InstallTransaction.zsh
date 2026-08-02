#!/bin/zsh

# Shared by BUILD.command and its fault-injection regression test. Callers own
# the user-facing error reporting; these functions only manage filesystem state.
INSTALL_TRANSACTION_ACTIVE=${INSTALL_TRANSACTION_ACTIVE:-0}
INSTALL_BACKUP=${INSTALL_BACKUP:-}
INSTALL_STAGING=${INSTALL_STAGING:-}

transactional_install() {
    local source_application="$1"
    local destination_application="$2"
    local backup_application="$3"

    [[ -d "$source_application" && "$source_application" == /* && "$source_application" == *.app ]] || return 70
    [[ -n "$destination_application" && "$destination_application" == /* && "$destination_application" == *.app ]] || return 71
    [[ -n "$backup_application" && "$backup_application" == /* && "$backup_application" == *.app ]] || return 72
    [[ "$source_application" != "$destination_application" && "$destination_application" != "/Applications.app" ]] || return 73

    INSTALL_STAGING="${destination_application%.app}.installing-$$.app"
    [[ "$INSTALL_STAGING" == "${destination_application%.app}.installing-"*.app ]] || return 74
    /bin/rm -rf "$INSTALL_STAGING"
    /usr/bin/ditto "$source_application" "$INSTALL_STAGING" || {
        /bin/rm -rf "$INSTALL_STAGING"
        INSTALL_STAGING=""
        return 75
    }

    INSTALL_TRANSACTION_ACTIVE=1
    INSTALL_BACKUP=""
    if [[ -e "$destination_application" ]]; then
        /bin/mv "$destination_application" "$backup_application" || return 76
        INSTALL_BACKUP="$backup_application"
    fi
    [[ "${LOGICLYRICS_TEST_INSTALL_FAULT:-}" != "after-backup" ]] || return 77
    /bin/mv "$INSTALL_STAGING" "$destination_application" || return 78
    INSTALL_STAGING=""
}

rollback_install_transaction() {
    local destination_application="$1"
    [[ "$INSTALL_TRANSACTION_ACTIVE" == "1" ]] || return
    if [[ -d "$destination_application" ]]; then
        local failed_application="${destination_application%.app}.failed-$(date +%Y%m%d-%H%M%S).app"
        /bin/mv "$destination_application" "$failed_application" 2>/dev/null || true
    fi
    if [[ -n "$INSTALL_BACKUP" && -d "$INSTALL_BACKUP" ]]; then
        /bin/mv "$INSTALL_BACKUP" "$destination_application" 2>/dev/null || true
    fi
    if [[ -n "$INSTALL_STAGING" && -d "$INSTALL_STAGING" ]]; then
        /bin/rm -rf "$INSTALL_STAGING" 2>/dev/null || true
    fi
    INSTALL_TRANSACTION_ACTIVE=0
    INSTALL_STAGING=""
}

commit_install_transaction() {
    INSTALL_TRANSACTION_ACTIVE=0
    INSTALL_STAGING=""
}
