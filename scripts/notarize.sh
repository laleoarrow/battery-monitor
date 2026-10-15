#!/bin/bash
# Submit one signed PKG or DMG and staple only after an Accepted response.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/local_cleanup.sh"
wattson_cleanup_init

TARGET_PATH="${1:-}"
[[ -n "$TARGET_PATH" ]] || {
    echo "usage: $0 /path/to/signed.pkg-or.dmg" >&2
    exit 2
}
[[ -f "$TARGET_PATH" && ! -L "$TARGET_PATH" ]] || {
    echo "notarize.sh: target must be a regular file: $TARGET_PATH" >&2
    exit 1
}
case "$TARGET_PATH" in
    *.pkg|*.dmg) ;;
    *) echo "notarize.sh: only PKG and DMG artifacts are supported" >&2; exit 2 ;;
esac

NOTARY_ARGUMENTS=()
if [[ -n "${WATTSON_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    NOTARY_ARGUMENTS=(--keychain-profile "$WATTSON_NOTARY_KEYCHAIN_PROFILE")
elif [[ -n "${WATTSON_NOTARY_KEY_PATH:-}" \
    || -n "${WATTSON_NOTARY_KEY_ID:-}" \
    || -n "${WATTSON_NOTARY_ISSUER:-}" ]]; then
    if [[ -z "${WATTSON_NOTARY_KEY_PATH:-}" \
        || -z "${WATTSON_NOTARY_KEY_ID:-}" \
        || -z "${WATTSON_NOTARY_ISSUER:-}" ]]; then
        echo "notarize.sh: API-key mode requires key path, key ID, and issuer" >&2
        exit 1
    fi
    [[ -f "$WATTSON_NOTARY_KEY_PATH" ]] || {
        echo "notarize.sh: API key file is missing" >&2
        exit 1
    }
    NOTARY_ARGUMENTS=(
        --key "$WATTSON_NOTARY_KEY_PATH"
        --key-id "$WATTSON_NOTARY_KEY_ID"
        --issuer "$WATTSON_NOTARY_ISSUER"
    )
else
    echo "notarize.sh: configure a keychain profile or all three API-key variables" >&2
    exit 1
fi

NOTARY_TIMEOUT="${WATTSON_NOTARY_TIMEOUT:-1h}"
umask 077
SCRATCH_PARENT="${WATTSON_RELEASE_BUILD_ROOT:-$ROOT_DIR/.build/local.noindex}"
/bin/mkdir -p "$SCRATCH_PARENT"
TEMP_DIR="$(/usr/bin/mktemp -d "$SCRATCH_PARENT/notary.XXXXXX")"
wattson_cleanup_add_dir "$TEMP_DIR"
SUBMISSION_RESULT="$TEMP_DIR/submission.json"
NOTARY_LOG="$TEMP_DIR/log.json"

echo "Submitting $(/usr/bin/basename "$TARGET_PATH") for Apple notarization..."
if ! wattson_run /usr/bin/xcrun notarytool submit \
        "$TARGET_PATH" \
        "${NOTARY_ARGUMENTS[@]}" \
        --wait \
        --timeout "$NOTARY_TIMEOUT" \
        --output-format json > "$SUBMISSION_RESULT"; then
    echo "notarize.sh: Apple notarization submission failed" >&2
    [[ ! -s "$SUBMISSION_RESULT" ]] || /bin/cat "$SUBMISSION_RESULT" >&2
    exit 1
fi

if ! NOTARY_STATUS="$(/usr/bin/plutil -extract status raw "$SUBMISSION_RESULT" 2>/dev/null)"; then
    echo "notarize.sh: submission response did not contain a valid status" >&2
    /bin/cat "$SUBMISSION_RESULT" >&2
    exit 1
fi
if ! SUBMISSION_ID="$(/usr/bin/plutil -extract id raw "$SUBMISSION_RESULT" 2>/dev/null)" \
    || [[ -z "$SUBMISSION_ID" ]]; then
    echo "notarize.sh: submission response did not contain a valid submission ID" >&2
    /bin/cat "$SUBMISSION_RESULT" >&2
    exit 1
fi

echo "Fetching Apple notarization log for submission $SUBMISSION_ID..."
if ! wattson_run /usr/bin/xcrun notarytool log \
        "$SUBMISSION_ID" \
        "$NOTARY_LOG" \
        "${NOTARY_ARGUMENTS[@]}" \
        --output-format json; then
    echo "notarize.sh: could not fetch the notarization log for submission $SUBMISSION_ID" >&2
    exit 1
fi

if ! NOTARY_ISSUES_TYPE="$(/usr/bin/plutil -type issues "$NOTARY_LOG" 2>/dev/null)"; then
    echo "notarize.sh: notarization log did not contain valid issue data" >&2
    /bin/cat "$NOTARY_LOG" >&2
    exit 1
fi
case "$NOTARY_ISSUES_TYPE" in
    array)
        if ! NOTARY_ISSUE_COUNT="$(/usr/bin/plutil -extract issues raw "$NOTARY_LOG" 2>/dev/null)"; then
            echo "notarize.sh: could not count notarization log issues" >&2
            /bin/cat "$NOTARY_LOG" >&2
            exit 1
        fi
        ;;
    "(any)")
        # notarytool represents no issues as JSON null on some Xcode versions.
        NOTARY_ISSUE_COUNT=0
        ;;
    *)
        echo "notarize.sh: notarization log issue data has an unexpected type" >&2
        /bin/cat "$NOTARY_LOG" >&2
        exit 1
        ;;
esac

if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
    echo "notarize.sh: Apple did not accept submission $SUBMISSION_ID (status: $NOTARY_STATUS)" >&2
    /bin/cat "$NOTARY_LOG" >&2
    exit 1
fi
if [[ "$NOTARY_ISSUE_COUNT" != "0" ]]; then
    echo "notarize.sh: Apple reported $NOTARY_ISSUE_COUNT issue(s) for submission $SUBMISSION_ID" >&2
    /bin/cat "$NOTARY_LOG" >&2
    exit 1
fi

wattson_run /usr/bin/xcrun stapler staple -v "$TARGET_PATH"
wattson_run /usr/bin/xcrun stapler validate -v "$TARGET_PATH"
echo "Notarization accepted and ticket stapled: $TARGET_PATH"
