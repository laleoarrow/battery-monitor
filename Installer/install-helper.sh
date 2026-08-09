#!/bin/bash
# Fixed-command privileged phase for Install Wattson.app.
set -euo pipefail
umask 022

readonly HELPER_LABEL="com.leoarrow.wattson.helper"
readonly HELPER_TARGET="system/$HELPER_LABEL"
readonly HELPER_BIN="/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper"
readonly HELPER_PLIST="/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist"
readonly HELPER_SOCKET="/var/run/wattson-helper.sock"
readonly DUPLICATE_APP="/Applications/Wattson.app"
readonly DUPLICATE_BACKUP="/Applications/.Wattson.removed-by-installer.$$.app"
readonly LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd)"
readonly SCRIPT_DIR
readonly PAYLOAD_DIR="$SCRIPT_DIR/Payload"
readonly SOURCE_HELPER="$PAYLOAD_DIR/com.leoarrow.wattson.helper"
readonly SOURCE_PLIST="$PAYLOAD_DIR/com.leoarrow.wattson.helper.plist"
readonly HELPER_CANDIDATE="${HELPER_BIN}.installing.$$"
readonly PLIST_CANDIDATE="${HELPER_PLIST}.installing.$$"
readonly BACKUP_DIR="$SCRIPT_DIR/Previous"
readonly BACKUP_HELPER="$BACKUP_DIR/$HELPER_LABEL"
readonly BACKUP_PLIST="$BACKUP_DIR/${HELPER_LABEL}.plist"

had_helper=0
had_plist=0
old_service_loaded=0
old_service_disabled=0
replacement_started=0
duplicate_moved=0

fail() {
    echo "Install Wattson: $*" >&2
    exit 1
}

validate_helper() {
    local helper_path="$1"
    /usr/bin/codesign --verify --strict "$helper_path"
}

validate_plist() {
    local plist_path="$1"
    local description="$2"
    /usr/bin/plutil -lint "$plist_path" >/dev/null
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :Label' "$plist_path")" == "$HELPER_LABEL" ]] \
        || fail "$description label does not match"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$plist_path")" == "$HELPER_BIN" ]] \
        || fail "$description executable does not match"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :Sockets:Listener:SockPathName' "$plist_path")" == "$HELPER_SOCKET" ]] \
        || fail "$description socket does not match"
}

stop_loaded_helper() {
    local attempt

    if ! /bin/launchctl print "$HELPER_TARGET" >/dev/null 2>&1; then
        return 0
    fi
    /bin/launchctl bootout "$HELPER_TARGET" || return 1
    for ((attempt = 0; attempt < 10; attempt++)); do
        if ! /bin/launchctl print "$HELPER_TARGET" >/dev/null 2>&1; then
            return 0
        fi
        /bin/sleep 0.1
    done
    return 1
}

rollback_helper_install() {
    local status="$?"
    local restore_ok=1
    trap - EXIT HUP INT TERM
    set +e

    /bin/rm -f -- "$HELPER_CANDIDATE" "$PLIST_CANDIDATE"
    if [[ "$status" != "0" && "$replacement_started" == "1" ]]; then
        if stop_loaded_helper >/dev/null 2>&1; then
            /bin/rm -f -- "$HELPER_SOCKET" "$HELPER_BIN" "$HELPER_PLIST"
            if [[ "$had_helper" == "1" ]]; then
                /usr/bin/install -o root -g wheel -m 544 "$BACKUP_HELPER" "$HELPER_BIN" \
                    || restore_ok=0
            fi
            if [[ "$had_plist" == "1" ]]; then
                /usr/bin/install -o root -g wheel -m 644 "$BACKUP_PLIST" "$HELPER_PLIST" \
                    || restore_ok=0
            fi
            if [[ "$old_service_loaded" == "1" && "$had_helper" == "1" && "$had_plist" == "1" ]]; then
                if [[ "$old_service_disabled" == "1" ]]; then
                    /bin/launchctl enable "$HELPER_TARGET" >/dev/null 2>&1 \
                        || restore_ok=0
                fi
                /bin/launchctl bootstrap system "$HELPER_PLIST" >/dev/null 2>&1 \
                    || restore_ok=0
                /bin/launchctl print "$HELPER_TARGET" >/dev/null 2>&1 \
                    || restore_ok=0
            fi
            if [[ "$old_service_disabled" == "1" ]]; then
                /bin/launchctl disable "$HELPER_TARGET" >/dev/null 2>&1 \
                    || restore_ok=0
            fi
        else
            restore_ok=0
        fi
    fi
    if [[ "$status" != "0" && "$duplicate_moved" == "1" ]]; then
        if [[ ! -e "$DUPLICATE_APP" && ! -L "$DUPLICATE_APP" ]]; then
            /bin/mv -f -- "$DUPLICATE_BACKUP" "$DUPLICATE_APP" || restore_ok=0
            "$LSREGISTER" -f "$DUPLICATE_APP" >/dev/null 2>&1 || restore_ok=0
        else
            restore_ok=0
        fi
    elif [[ "$status" == "0" && "$duplicate_moved" == "1" ]]; then
        /bin/rm -rf -- "$DUPLICATE_BACKUP" || true
    fi
    if [[ "$restore_ok" == "1" ]]; then
        /bin/rm -rf -- "$BACKUP_DIR"
    else
        echo "Install Wattson: helper rollback backup preserved at $BACKUP_DIR" >&2
    fi
    exit "$status"
}

abort_helper_install() {
    exit 130
}

trap rollback_helper_install EXIT
trap abort_helper_install HUP INT TERM

[[ "$(/usr/bin/id -u)" == "0" ]] || fail "administrator privileges are required"
[[ -f "$SOURCE_HELPER" && ! -L "$SOURCE_HELPER" ]] || fail "helper payload is missing"
[[ -f "$SOURCE_PLIST" && ! -L "$SOURCE_PLIST" ]] || fail "helper plist is missing"

validate_helper "$SOURCE_HELPER"
validate_plist "$SOURCE_PLIST" "helper plist"

/usr/bin/install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools
/usr/bin/install -d -o root -g wheel -m 700 "$BACKUP_DIR"

if [[ -e "$HELPER_BIN" || -L "$HELPER_BIN" ]]; then
    [[ -f "$HELPER_BIN" && ! -L "$HELPER_BIN" ]] || fail "existing helper is not a regular file"
    /usr/bin/install -o root -g wheel -m 544 "$HELPER_BIN" "$BACKUP_HELPER"
    had_helper=1
fi
if [[ -e "$HELPER_PLIST" || -L "$HELPER_PLIST" ]]; then
    [[ -f "$HELPER_PLIST" && ! -L "$HELPER_PLIST" ]] || fail "existing helper plist is not a regular file"
    /usr/bin/install -o root -g wheel -m 644 "$HELPER_PLIST" "$BACKUP_PLIST"
    had_plist=1
fi
if ! disabled_services="$(/bin/launchctl print-disabled system 2>/dev/null)"; then
    fail "helper launchd state could not be inspected"
fi
case "$disabled_services" in
    *"\"$HELPER_LABEL\" => disabled"*|*"\"$HELPER_LABEL\" => true"*)
        old_service_disabled=1
        ;;
esac
if /bin/launchctl print "$HELPER_TARGET" >/dev/null 2>&1; then
    old_service_loaded=1
fi

# Validate destination-filesystem candidates before the old service is touched.
/usr/bin/install -o root -g wheel -m 544 "$SOURCE_HELPER" "$HELPER_CANDIDATE"
/usr/bin/install -o root -g wheel -m 644 "$SOURCE_PLIST" "$PLIST_CANDIDATE"
validate_helper "$HELPER_CANDIDATE"
validate_plist "$PLIST_CANDIDATE" "candidate helper plist"

replacement_started=1
stop_loaded_helper || fail "existing helper service could not be stopped"
/bin/rm -f -- "$HELPER_SOCKET"
/bin/mv -f -- "$HELPER_CANDIDATE" "$HELPER_BIN"
/bin/mv -f -- "$PLIST_CANDIDATE" "$HELPER_PLIST"
validate_helper "$HELPER_BIN"
validate_plist "$HELPER_PLIST" "installed helper plist"
if [[ "$old_service_disabled" == "1" ]]; then
    /bin/launchctl enable "$HELPER_TARGET"
fi
/bin/launchctl bootstrap system "$HELPER_PLIST"
/bin/launchctl print "$HELPER_TARGET" >/dev/null
"$HELPER_BIN" --health-probe

# This is deliberately the final fallible installation step. The new app has
# already passed its menu-bar readiness check, and the helper has answered a
# console-user socket probe while both rollback backups still exist.
if [[ -d "$DUPLICATE_APP" && ! -L "$DUPLICATE_APP" ]]; then
    duplicate_info="$DUPLICATE_APP/Contents/Info.plist"
    if [[ -f "$duplicate_info" && ! -L "$duplicate_info" ]]; then
        duplicate_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$duplicate_info" 2>/dev/null || true)"
        if [[ "$duplicate_id" == "com.leoarrow.wattson" ]]; then
            [[ ! -e "$DUPLICATE_BACKUP" && ! -L "$DUPLICATE_BACKUP" ]] \
                || fail "duplicate-app rollback path already exists"
            /bin/mv -- "$DUPLICATE_APP" "$DUPLICATE_BACKUP"
            duplicate_moved=1
            "$LSREGISTER" -u "$DUPLICATE_BACKUP" >/dev/null 2>&1 || true
            /usr/bin/pkill -f '^/Applications/Wattson\.app/Contents/MacOS/Wattson([[:space:]]|$)' \
                >/dev/null 2>&1 || true
        fi
    fi
fi
