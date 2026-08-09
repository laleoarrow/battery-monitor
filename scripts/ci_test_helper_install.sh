#!/bin/bash
# Exercise the packaged privileged helper only on a disposable GitHub macOS ARM runner.
set -euo pipefail
umask 022

readonly HELPER_LABEL="com.leoarrow.wattson.helper"
readonly HELPER_TARGET="system/$HELPER_LABEL"
readonly HELPER_BIN="/Library/PrivilegedHelperTools/$HELPER_LABEL"
readonly HELPER_PLIST="/Library/LaunchDaemons/$HELPER_LABEL.plist"
readonly HELPER_SOCKET="/var/run/wattson-helper.sock"
readonly DUPLICATE_APP="/Applications/Wattson.app"
readonly APP_BUNDLE_ID="com.leoarrow.wattson"

fail() {
    echo "CI helper install test: $*" >&2
    exit 1
}

[[ "${GITHUB_ACTIONS:-}" == "true" ]] || fail "GitHub Actions is required"
[[ "${RUNNER_OS:-}" == "macOS" ]] || fail "a macOS runner is required"
[[ "${RUNNER_ENVIRONMENT:-}" == "github-hosted" ]] || fail "a GitHub-hosted ephemeral runner is required"
[[ "$(/usr/bin/uname -m)" == "arm64" ]] || fail "an Apple Silicon runner is required"
[[ -n "${RUNNER_TEMP:-}" ]] || fail "RUNNER_TEMP is required"
[[ "$#" == "1" ]] || fail "usage: $0 /verified/path/to/Wattson.dmg"

RUNNER_TEMP_DIR="$(cd -P -- "$RUNNER_TEMP" 2>/dev/null && pwd)" \
    || fail "RUNNER_TEMP is not an existing directory"
[[ "$RUNNER_TEMP_DIR" != "/" ]] || fail "RUNNER_TEMP must not be the filesystem root"
[[ -d "$RUNNER_TEMP_DIR" ]] || fail "RUNNER_TEMP is not a directory"
readonly RUNNER_TEMP_DIR

assert_runner_temp_path() {
    case "$1" in
        "$RUNNER_TEMP_DIR"/*) ;;
        *) fail "path is outside verified RUNNER_TEMP: $1" ;;
    esac
}

[[ -f "$1" && ! -L "$1" ]] || fail "DMG input must be a regular file"
DMG_PATH="$(cd -P -- "$(dirname -- "$1")" && pwd)/$(/usr/bin/basename -- "$1")"
assert_runner_temp_path "$DMG_PATH"
readonly DMG_PATH

for system_path in "$HELPER_BIN" "$HELPER_PLIST" "$HELPER_SOCKET" "$DUPLICATE_APP"; do
    [[ ! -e "$system_path" && ! -L "$system_path" ]] \
        || fail "refusing to touch pre-existing system path: $system_path"
done

SUDO=(/usr/bin/sudo -n)
"${SUDO[@]}" /usr/bin/true || fail "passwordless sudo is required on the ephemeral runner"

# Return 0 when loaded, 1 only for launchd's explicit not-found response, and
# 2 when launchd could not be queried reliably.
probe_launchd_service() {
    local output
    if output="$(
        "${SUDO[@]}" /usr/bin/env -i \
            PATH=/usr/bin:/bin:/usr/sbin:/sbin \
            LANG=C \
            LC_ALL=C \
            /bin/launchctl print "$HELPER_TARGET" 2>&1
    )"; then
        return 0
    fi
    case "$output" in
        *"Could not find service"*|*"Could not find specified service"*)
            return 1
            ;;
        *)
            echo "CI helper install test: unexpected launchd query failure: $output" >&2
            return 2
            ;;
    esac
}

CONSOLE_UID="$(/usr/bin/stat -f '%u' /dev/console)" \
    || fail "could not inspect the runner console owner"
[[ "$CONSOLE_UID" =~ ^[0-9]+$ && "$CONSOLE_UID" != "0" ]] \
    || fail "the hosted runner has no non-root console user for the helper health probe"
[[ "$CONSOLE_UID" == "$(/usr/bin/id -u)" ]] \
    || fail "the Actions account is not the hosted runner console user"
readonly CONSOLE_UID
if probe_launchd_service; then
    fail "refusing to touch pre-existing launchd service: $HELPER_TARGET"
else
    launchd_probe_status="$?"
    [[ "$launchd_probe_status" == "1" ]] \
        || fail "could not confirm that the launchd service is absent"
fi
disabled_services="$("${SUDO[@]}" /bin/launchctl print-disabled system)" \
    || fail "could not inspect existing launchd disabled state"
case "$disabled_services" in
    *"\"$HELPER_LABEL\" => disabled"*|*"\"$HELPER_LABEL\" => true"*)
        fail "refusing to touch pre-existing disabled launchd service: $HELPER_TARGET"
        ;;
esac

MOUNT_DIR="$(mktemp -d "$RUNNER_TEMP_DIR/wattson-helper-mount.XXXXXX")"
assert_runner_temp_path "$MOUNT_DIR"
readonly MOUNT_DIR

ROOT_STAGE=""
MOUNTED=0
HELPER_INSTALL_STARTED=0

assert_root_stage_path() {
    local suffix
    case "$1" in
        /private/tmp/com.leoarrow.wattson.ci.*)
            suffix="${1#/private/tmp/com.leoarrow.wattson.ci.}"
            [[ -n "$suffix" && "$suffix" != */* ]] \
                || fail "invalid root stage suffix"
            ;;
        *) fail "root stage escaped its fixed /private/tmp prefix" ;;
    esac
}

collect_failure_logs() {
    echo "::group::Wattson helper diagnostics"
    "${SUDO[@]}" /bin/launchctl print "$HELPER_TARGET" || true
    "${SUDO[@]}" /bin/launchctl print-disabled system || true
    "${SUDO[@]}" /usr/bin/xattr "$HELPER_BIN" || true
    "${SUDO[@]}" /usr/bin/xattr "$HELPER_PLIST" || true
    /usr/bin/log show --style compact --last 10m \
        --predicate '(process == "wattson-helper") OR (eventMessage CONTAINS[c] "Wattson")' \
        || true
    echo "::endgroup::"
}

cleanup() {
    local status="$1"
    local cleanup_status="$status"
    local disabled_after_cleanup
    local system_path
    local attempt
    local launchd_probe_status
    local job_absent=0
    trap - EXIT

    if [[ "$status" != "0" ]]; then
        collect_failure_logs
    fi
    if [[ "$HELPER_INSTALL_STARTED" == "1" ]]; then
        "${SUDO[@]}" /bin/launchctl bootout "$HELPER_TARGET" >/dev/null 2>&1 || true
        for ((attempt = 0; attempt < 20; attempt++)); do
            if probe_launchd_service; then
                /bin/sleep 0.1
                continue
            else
                launchd_probe_status="$?"
            fi
            if [[ "$launchd_probe_status" == "1" ]]; then
                job_absent=1
            fi
            break
        done
        if [[ "$job_absent" != "1" ]]; then
            echo "CI helper install test: cleanup could not confirm launchd service removal; preserving files" >&2
            cleanup_status=1
        else
            "${SUDO[@]}" /bin/launchctl enable "$HELPER_TARGET" >/dev/null 2>&1 \
                || cleanup_status=1
            "${SUDO[@]}" /bin/rm -f -- "$HELPER_SOCKET" "$HELPER_PLIST" "$HELPER_BIN" \
                || cleanup_status=1

            if probe_launchd_service; then
                echo "CI helper install test: cleanup left launchd service loaded" >&2
                cleanup_status=1
            else
                launchd_probe_status="$?"
                [[ "$launchd_probe_status" == "1" ]] || cleanup_status=1
            fi
            for system_path in "$HELPER_BIN" "$HELPER_PLIST" "$HELPER_SOCKET"; do
                if [[ -e "$system_path" || -L "$system_path" ]]; then
                    echo "CI helper install test: cleanup left system path: $system_path" >&2
                    cleanup_status=1
                fi
            done
            if disabled_after_cleanup="$("${SUDO[@]}" /bin/launchctl print-disabled system)"; then
                case "$disabled_after_cleanup" in
                    *"\"$HELPER_LABEL\" => disabled"*|*"\"$HELPER_LABEL\" => true"*)
                        echo "CI helper install test: cleanup left launchd service disabled" >&2
                        cleanup_status=1
                        ;;
                esac
            else
                cleanup_status=1
            fi
        fi
    fi
    if [[ "$MOUNTED" == "1" ]]; then
        /usr/bin/hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || cleanup_status=1
    fi
    assert_runner_temp_path "$MOUNT_DIR"
    /bin/rm -rf -- "$MOUNT_DIR" || cleanup_status=1
    [[ ! -e "$MOUNT_DIR" ]] || cleanup_status=1
    if [[ -n "$ROOT_STAGE" ]]; then
        assert_root_stage_path "$ROOT_STAGE"
        "${SUDO[@]}" /bin/rm -rf -- "$ROOT_STAGE" || cleanup_status=1
        [[ ! -e "$ROOT_STAGE" && ! -L "$ROOT_STAGE" ]] || cleanup_status=1
    fi
    exit "$cleanup_status"
}
trap 'cleanup "$?"' EXIT

ROOT_STAGE="$(
    "${SUDO[@]}" /usr/bin/env -i \
        PATH=/usr/bin:/bin:/usr/sbin:/sbin \
        /usr/bin/mktemp -d /private/tmp/com.leoarrow.wattson.ci.XXXXXX
)" || fail "could not create the root-owned CI stage"
assert_root_stage_path "$ROOT_STAGE"
if ! "${SUDO[@]}" /bin/test -d "$ROOT_STAGE" \
    || "${SUDO[@]}" /bin/test -L "$ROOT_STAGE"; then
    fail "root stage is not a physical directory"
fi
[[ "$("${SUDO[@]}" /usr/bin/stat -f '%u:%g:%OLp' "$ROOT_STAGE")" == "0:0:700" ]] \
    || fail "root stage ownership or mode does not match root:wheel 0700"
readonly ROOT_STAGE
readonly STAGED_RESOURCES="$ROOT_STAGE"

/usr/bin/hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_DIR" "$DMG_PATH" >/dev/null
MOUNTED=1
readonly INSTALLER_APP="$MOUNT_DIR/Install Wattson.app"
readonly INSTALLER_EXECUTABLE="$INSTALLER_APP/Contents/MacOS/Install Wattson"
readonly INSTALLER_RESOURCES="$INSTALLER_APP/Contents/Resources"
[[ -d "$INSTALLER_APP" && ! -L "$INSTALLER_APP" ]] || fail "packaged installer is missing"
[[ -x "$INSTALLER_EXECUTABLE" && ! -L "$INSTALLER_EXECUTABLE" ]] \
    || fail "packaged installer executable is missing"
/usr/bin/codesign --verify --deep --strict "$INSTALLER_APP"
"$INSTALLER_EXECUTABLE" --verify

stage_file_as_root() {
    local source_path="$1"
    local destination_path="$2"
    local mode="$3"
    local source_hash
    local staged_hash

    source_hash="$(/usr/bin/shasum -a 256 "$source_path" | /usr/bin/awk '{print $1}')"
    "${SUDO[@]}" /usr/bin/install -o root -g wheel -m "$mode" \
        "$source_path" "$destination_path"
    staged_hash="$("${SUDO[@]}" /usr/bin/shasum -a 256 "$destination_path" | /usr/bin/awk '{print $1}')"
    [[ "$source_hash" == "$staged_hash" ]] || fail "root staging hash mismatch"
}

"${SUDO[@]}" /usr/bin/install -d -o root -g wheel -m 700 \
    "$STAGED_RESOURCES/Payload"
stage_file_as_root \
    "$INSTALLER_RESOURCES/install-helper.sh" \
    "$STAGED_RESOURCES/install-helper.sh" \
    500
stage_file_as_root \
    "$INSTALLER_RESOURCES/Payload/$HELPER_LABEL" \
    "$STAGED_RESOURCES/Payload/$HELPER_LABEL" \
    500
stage_file_as_root \
    "$INSTALLER_RESOURCES/Payload/$HELPER_LABEL.plist" \
    "$STAGED_RESOURCES/Payload/$HELPER_LABEL.plist" \
    400
require_root_regular_file() {
    local item_path="$1"
    local description="$2"
    if ! "${SUDO[@]}" /bin/test -f "$item_path" \
        || "${SUDO[@]}" /bin/test -L "$item_path"; then
        fail "$description is missing or is a symbolic link"
    fi
}

require_root_regular_file \
    "$STAGED_RESOURCES/install-helper.sh" \
    "packaged helper install script"
require_root_regular_file \
    "$STAGED_RESOURCES/Payload/$HELPER_LABEL" \
    "packaged helper binary"
require_root_regular_file \
    "$STAGED_RESOURCES/Payload/$HELPER_LABEL.plist" \
    "packaged helper plist"

# Model the browser-origin quarantine that can be propagated from a downloaded
# image. The production helper installer must remove it from final candidates.
readonly CI_QUARANTINE_VALUE="0081;00000000;GitHubActions;Wattson"
"${SUDO[@]}" /usr/bin/xattr -w com.apple.quarantine "$CI_QUARANTINE_VALUE" \
    "$STAGED_RESOURCES/Payload/$HELPER_LABEL"
"${SUDO[@]}" /usr/bin/xattr -w com.apple.quarantine "$CI_QUARANTINE_VALUE" \
    "$STAGED_RESOURCES/Payload/$HELPER_LABEL.plist"

assert_quarantine_present() {
    local item_path="$1"
    local attributes
    attributes="$("${SUDO[@]}" /usr/bin/xattr "$item_path")" \
        || fail "could not inspect staged quarantine attributes"
    case $'\n'"$attributes"$'\n' in
        *$'\ncom.apple.quarantine\n'*) ;;
        *) fail "staged quarantine simulation was not applied" ;;
    esac
}

assert_quarantine_absent() {
    local item_path="$1"
    local attributes
    attributes="$("${SUDO[@]}" /usr/bin/xattr "$item_path")" \
        || fail "could not inspect installed extended attributes"
    case $'\n'"$attributes"$'\n' in
        *$'\ncom.apple.quarantine\n'*)
            fail "installed item retains com.apple.quarantine: $item_path"
            ;;
    esac
}

assert_quarantine_present "$STAGED_RESOURCES/Payload/$HELPER_LABEL"
assert_quarantine_present "$STAGED_RESOURCES/Payload/$HELPER_LABEL.plist"

/usr/bin/hdiutil detach "$MOUNT_DIR" >/dev/null
MOUNTED=0

install_and_verify() {
    HELPER_INSTALL_STARTED=1
    "${SUDO[@]}" /usr/bin/env -i \
        PATH=/usr/bin:/bin:/usr/sbin:/sbin \
        HOME=/var/root \
        USER=root \
        LOGNAME=root \
        /bin/bash -p "$STAGED_RESOURCES/install-helper.sh"
    "${SUDO[@]}" /bin/launchctl print "$HELPER_TARGET" >/dev/null
    "${SUDO[@]}" "$HELPER_BIN" --health-probe
    "${SUDO[@]}" /usr/bin/codesign --verify --strict "$HELPER_BIN"
    [[ "$("${SUDO[@]}" /usr/bin/shasum -a 256 "$HELPER_BIN" | /usr/bin/awk '{print $1}')" \
        == "$("${SUDO[@]}" /usr/bin/shasum -a 256 "$STAGED_RESOURCES/Payload/$HELPER_LABEL" | /usr/bin/awk '{print $1}')" ]] \
        || fail "installed helper hash does not match the root stage"
    [[ "$("${SUDO[@]}" /usr/bin/shasum -a 256 "$HELPER_PLIST" | /usr/bin/awk '{print $1}')" \
        == "$("${SUDO[@]}" /usr/bin/shasum -a 256 "$STAGED_RESOURCES/Payload/$HELPER_LABEL.plist" | /usr/bin/awk '{print $1}')" ]] \
        || fail "installed helper plist hash does not match the root stage"
    [[ "$("${SUDO[@]}" /usr/bin/stat -f '%u:%g:%OLp' "$HELPER_BIN")" == "0:0:544" ]] \
        || fail "installed helper ownership or mode is not root:wheel 0544"
    [[ "$("${SUDO[@]}" /usr/bin/stat -f '%u:%g:%OLp' "$HELPER_PLIST")" == "0:0:644" ]] \
        || fail "installed plist ownership or mode is not root:wheel 0644"
    assert_quarantine_absent "$HELPER_BIN"
    assert_quarantine_absent "$HELPER_PLIST"
    [[ "$("${SUDO[@]}" /usr/libexec/PlistBuddy -c 'Print :Label' "$HELPER_PLIST")" == "$HELPER_LABEL" ]] \
        || fail "installed plist label does not match"
    [[ "$("${SUDO[@]}" /usr/libexec/PlistBuddy -c 'Print :AssociatedBundleIdentifiers:0' "$HELPER_PLIST")" == "$APP_BUNDLE_ID" ]] \
        || fail "installed plist association does not match"
    [[ "$("${SUDO[@]}" /usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$HELPER_PLIST")" == "$HELPER_BIN" ]] \
        || fail "installed plist executable does not match"
    [[ "$("${SUDO[@]}" /usr/libexec/PlistBuddy -c 'Print :Sockets:Listener:SockPathName' "$HELPER_PLIST")" == "$HELPER_SOCKET" ]] \
        || fail "installed plist socket does not match"
}

install_and_verify

echo "Checking disabled-service reinstall path..."
"${SUDO[@]}" /bin/launchctl bootout "$HELPER_TARGET"
"${SUDO[@]}" /bin/launchctl disable "$HELPER_TARGET"
disabled_services="$("${SUDO[@]}" /bin/launchctl print-disabled system)"
case "$disabled_services" in
    *"\"$HELPER_LABEL\" => disabled"*|*"\"$HELPER_LABEL\" => true"*) ;;
    *) fail "launchd did not retain the disabled state" ;;
esac

install_and_verify
disabled_services="$("${SUDO[@]}" /bin/launchctl print-disabled system)"
case "$disabled_services" in
    *"\"$HELPER_LABEL\" => disabled"*|*"\"$HELPER_LABEL\" => true"*)
        fail "reinstall left the helper disabled"
        ;;
esac

echo "CI helper install test passed."
cleanup 0
