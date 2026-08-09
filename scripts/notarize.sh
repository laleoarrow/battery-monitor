#!/bin/bash
# Submit one signed PKG or DMG and staple only after an Accepted response.
set -euo pipefail

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
elif [[ -n "${WATTSON_NOTARY_KEY_PATH:-}" && -n "${WATTSON_NOTARY_KEY_ID:-}" ]]; then
    [[ -f "$WATTSON_NOTARY_KEY_PATH" ]] || {
        echo "notarize.sh: API key file is missing" >&2
        exit 1
    }
    NOTARY_ARGUMENTS=(
        --key "$WATTSON_NOTARY_KEY_PATH"
        --key-id "$WATTSON_NOTARY_KEY_ID"
    )
    if [[ -n "${WATTSON_NOTARY_ISSUER:-}" ]]; then
        NOTARY_ARGUMENTS+=(--issuer "$WATTSON_NOTARY_ISSUER")
    fi
else
    echo "notarize.sh: configure WATTSON_NOTARY_KEYCHAIN_PROFILE or the API key variables" >&2
    exit 1
fi

NOTARY_TIMEOUT="${WATTSON_NOTARY_TIMEOUT:-1h}"
RESULT_FILE="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/wattson-notary.XXXXXX")"
cleanup() {
    /bin/rm -f -- "$RESULT_FILE"
}
trap cleanup EXIT

echo "Submitting $(/usr/bin/basename "$TARGET_PATH") for Apple notarization..."
/usr/bin/xcrun notarytool submit \
    "$TARGET_PATH" \
    "${NOTARY_ARGUMENTS[@]}" \
    --wait \
    --timeout "$NOTARY_TIMEOUT" \
    --output-format json > "$RESULT_FILE"

NOTARY_STATUS="$(/usr/bin/plutil -extract status raw "$RESULT_FILE" 2>/dev/null || true)"
if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
    echo "notarize.sh: Apple did not accept the artifact (status: ${NOTARY_STATUS:-unknown})" >&2
    /bin/cat "$RESULT_FILE" >&2
    exit 1
fi

/usr/bin/xcrun stapler staple -v "$TARGET_PATH"
/usr/bin/xcrun stapler validate -v "$TARGET_PATH"
echo "Notarization accepted and ticket stapled: $TARGET_PATH"
