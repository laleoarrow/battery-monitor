#!/bin/bash
# Read-only, source-visible support collection for Wattson issue #19.
set -euo pipefail
umask 077
export LC_ALL=C
export COPYFILE_DISABLE=1

SUPPORT_DIR="$(cd "$(/usr/bin/dirname "$0")" && /bin/pwd)"
# shellcheck source=lifecycle.sh
source "$SUPPORT_DIR/lifecycle.sh"
OUTPUT_DIR="$HOME/Desktop"
COLLECT_ONLY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --collect-only) COLLECT_ONLY=1; shift ;;
        --output)
            [[ $# -ge 2 && -n "$2" ]] || { echo 'Missing --output directory.' >&2; exit 2; }
            OUTPUT_DIR=$2; shift 2 ;;
        *) echo 'Usage: Collect-Wattson-Issue19.command [--collect-only] [--output DIRECTORY]' >&2; exit 2 ;;
    esac
done

/bin/mkdir -p -- "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && /bin/pwd)"
# FIFOs require a native local filesystem; output may be an external/shared disk.
support_begin "${TMPDIR:-/tmp}/Wattson-Issue19.noindex"
REPORT_DIR="$SUPPORT_SCRATCH/Wattson-Issue19"
/bin/mkdir "$REPORT_DIR"

echo 'Wattson #19: read-only support collection / 只读诊断收集'
echo 'No password, screenshots, permission changes, clipboard access or upload.'
echo '不需要密码；不会截图、修改权限、读取剪贴板或自动上传。'

# Bound every external probe. Only fixed, non-personal fields enter the report.
run_probe() {
    local key=$1 timeout_ticks=$2 tick=0 pid
    shift 2
    "$@" > "$SUPPORT_SCRATCH/$key.raw" 2>/dev/null &
    pid=$!
    support_track "$pid"
    while kill -0 "$pid" 2>/dev/null && [[ "$tick" -lt "$timeout_ticks" ]]; do
        /bin/sleep 0.1 &
        local sleeper=$!
        support_track "$sleeper"
        wait "$sleeper" || true
        support_forget "$sleeper"
        tick=$((tick + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
        support_stop "$pid"
        echo unavailable > "$SUPPORT_SCRATCH/$key.raw"
    elif wait "$pid"; then
        support_forget "$pid"
        [[ "$key" != signature ]] || echo verified > "$SUPPORT_SCRATCH/$key.raw"
    else
        support_forget "$pid"
        echo unavailable > "$SUPPORT_SCRATCH/$key.raw"
    fi
}

run_probe productVersion 30 /usr/bin/env SYSTEM_VERSION_COMPAT=0 /usr/bin/sw_vers -productVersion
run_probe buildVersion 30 /usr/bin/env SYSTEM_VERSION_COMPAT=0 /usr/bin/sw_vers -buildVersion
run_probe model 30 /usr/sbin/sysctl -n hw.model
run_probe architecture 30 /usr/bin/uname -m
run_probe signature 50 /usr/bin/codesign --verify --deep --strict /Applications/Wattson.app

run_probe snapshot 100 /usr/bin/osascript -l JavaScript "$SUPPORT_DIR/collect.js" snapshot "$SUPPORT_SCRATCH"
if [[ ! -s "$SUPPORT_SCRATCH/snapshot.raw" ]] || [[ "$(/bin/cat "$SUPPORT_SCRATCH/snapshot.raw")" == unavailable ]]; then
    echo 'Could not read the limited AppKit snapshot. No report was created.' >&2
    exit 1
fi
/bin/cp "$SUPPORT_SCRATCH/snapshot.raw" "$REPORT_DIR/environment.json"

: > "$SUPPORT_SCRATCH/events.ndjson"
TRACE_MODE=skipped-collect-only
if [[ "$COLLECT_ONLY" == 0 ]]; then
    run_probe plan 50 /usr/bin/osascript -l JavaScript "$SUPPORT_DIR/collect.js" plan "$SUPPORT_SCRATCH"
    TRACE_MODE="$(/bin/cat "$SUPPORT_SCRATCH/plan.raw")"
    case "$TRACE_MODE" in
        skipped-no-trace-4.3.3)
            echo 'Wattson 4.3.3 has no popup event recording; collecting environment only.'
            echo 'Wattson 4.3.3 没有点击事件记录，无需等待 60 秒；已收集环境信息。' ;;
        skipped-no-running-instance)
            echo 'Wattson is not running; collecting environment only.'
            echo '未检测到运行中的 Wattson，无需等待 60 秒；已收集环境信息。' ;;
        capture) ;;
        *) echo 'Could not determine the safe collection mode. No report was created.' >&2; exit 1 ;;
    esac
fi
if [[ "$TRACE_MODE" == capture ]]; then
    TRACE_MODE=captured
    echo ''
    echo 'For the next 60 seconds, click the Wattson menu-bar icon four times:'
    echo 'open → close → open → close. If a click fails, continue the same sequence.'
    echo '请在接下来 60 秒内点击 Wattson 图标四次：打开 → 关闭 → 打开 → 关闭。'
    echo '某次无响应也请继续；结束后会在桌面生成 ZIP，供你检查后手动附到 Issue。'
    /usr/bin/mkfifo "$SUPPORT_SCRATCH/events.pipe"
    /usr/bin/head -c 262144 < "$SUPPORT_SCRATCH/events.pipe" > "$SUPPORT_SCRATCH/events.ndjson" &
    reader=$!
    support_track "$reader"
    /usr/bin/log stream --level info --style ndjson \
        --predicate 'subsystem == "com.leoarrow.wattson" AND category == "popup-events"' \
        > "$SUPPORT_SCRATCH/events.pipe" 2>/dev/null &
    logger=$!
    support_track "$logger"
    /bin/sleep 60 &
    timer=$!
    support_track "$timer"
    wait "$timer"
    support_forget "$timer"
    support_stop "$logger"
    wait "$reader" || true
    support_forget "$reader"
fi

run_probe events 50 /usr/bin/osascript -l JavaScript "$SUPPORT_DIR/collect.js" events "$SUPPORT_SCRATCH" "$TRACE_MODE"
if [[ ! -s "$SUPPORT_SCRATCH/events.raw" ]] || [[ "$(/bin/cat "$SUPPORT_SCRATCH/events.raw")" == unavailable ]]; then
    echo 'Could not sanitize popup events. No report was created.' >&2
    exit 1
fi
/bin/cp "$SUPPORT_SCRATCH/events.raw" "$REPORT_DIR/popup-events.json"
/bin/cp "$SUPPORT_DIR/REPORT-README.txt" "$REPORT_DIR/README.txt"
REPORT_NAME="Wattson-Issue19-$(/bin/date -u +%Y%m%dT%H%M%SZ)-$$.zip"
ARCHIVE="$SUPPORT_SCRATCH/$REPORT_NAME"
/usr/bin/ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$REPORT_DIR" "$ARCHIVE"
/usr/bin/unzip -t "$ARCHIVE" >/dev/null
SUPPORT_OUTPUT_PARTIAL="$OUTPUT_DIR/.$REPORT_NAME.partial.noindex"
/bin/cp "$ARCHIVE" "$SUPPORT_OUTPUT_PARTIAL"
/usr/bin/cmp -s "$ARCHIVE" "$SUPPORT_OUTPUT_PARTIAL"
/bin/mv "$SUPPORT_OUTPUT_PARTIAL" "$OUTPUT_DIR/$REPORT_NAME"
SUPPORT_OUTPUT_PARTIAL=""
echo ''
echo "Saved / 已保存: $OUTPUT_DIR/$REPORT_NAME"
echo 'Unzip and review it, then attach the ZIP to GitHub issue #19.'
echo '请先解压检查内容，再把 ZIP 拖到 GitHub Issue #19 回复框手动提交。'
