#!/bin/bash
# Read-only, source-visible support collection; no Wattson CLI dependency.
set -euo pipefail
umask 077
export LC_ALL=C
export COPYFILE_DISABLE=1

case "${BASH_SOURCE[0]}:$PWD" in
    *$'\n'*|*$'\r'*) echo 'Paths containing line breaks are not supported.' >&2; exit 2 ;;
esac
SUPPORT_DIR="${BASH_SOURCE[0]%/*}"
[[ "$SUPPORT_DIR" != "${BASH_SOURCE[0]}" ]] || SUPPORT_DIR=.
# A suffix prevents command substitution from trimming a directory's final LF.
SUPPORT_DIR="$(cd "$SUPPORT_DIR" && printf '%s/' "$PWD")"
SUPPORT_DIR="${SUPPORT_DIR%/}"
case "$SUPPORT_DIR" in
    *$'\n'*|*$'\r'*) echo 'Paths containing line breaks are not supported.' >&2; exit 2 ;;
esac
# shellcheck source=lifecycle.sh
source "$SUPPORT_DIR/lifecycle.sh"
OUTPUT_DIR="$HOME/Desktop"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            [[ $# -ge 2 && -n "$2" ]] || { echo 'Missing --output directory.' >&2; exit 2; }
            OUTPUT_DIR=$2; shift 2 ;;
        *) echo 'Usage: Collect-Wattson-SystemBatteryIcon.command [--output DIRECTORY]' >&2; exit 2 ;;
    esac
done

support_validate_path "$OUTPUT_DIR"
support_begin "${TMPDIR:-/tmp}/Wattson-SystemBatteryIcon.noindex"
support_run /bin/mkdir -p -- "$OUTPUT_DIR"
support_run /bin/bash -c 'cd "$1" && pwd' -- "$OUTPUT_DIR" > "$SUPPORT_SCRATCH/output-directory"
OUTPUT_DIR=$(support_read_path "$SUPPORT_SCRATCH/output-directory")
REPORT_DIR="$SUPPORT_SCRATCH/Wattson-SystemBatteryIcon"
support_run /bin/mkdir "$REPORT_DIR"

echo 'Wattson 系统电池图标：只读诊断收集 / Read-only support collection'
echo '不需要密码或额外软件，不修改设置或权限，不截图，不自动上传。'
echo '通常十几秒内完成；完成后请检查桌面上的 ZIP，再手动附到 Issue。'

run_probe() {
    local key=$1 seconds=$2
    shift 2
    if support_run_for "$seconds" "$@" > "$SUPPORT_SCRATCH/$key.raw" 2>/dev/null; then
        [[ "$key" != signature ]] || echo verified > "$SUPPORT_SCRATCH/$key.raw"
    else
        echo unavailable > "$SUPPORT_SCRATCH/$key.raw"
    fi
}

run_probe productVersion 3 /usr/bin/env SYSTEM_VERSION_COMPAT=0 /usr/bin/sw_vers -productVersion
run_probe buildVersion 3 /usr/bin/env SYSTEM_VERSION_COMPAT=0 /usr/bin/sw_vers -buildVersion
run_probe architecture 3 /usr/bin/uname -m
run_probe signature 5 /usr/bin/codesign --verify --deep --strict /Applications/Wattson.app
# The Perl request itself has a four-second deadline; allow startup/output headroom.
run_probe health 6 /usr/bin/perl "$SUPPORT_DIR/socket_probe.pl" health
run_probe batteryIcon 6 /usr/bin/perl "$SUPPORT_DIR/socket_probe.pl" getSystemBatteryIconHidden
run_probe snapshot 10 /usr/bin/osascript -l JavaScript "$SUPPORT_DIR/collect.js" snapshot "$SUPPORT_SCRATCH"
SNAPSHOT=""
IFS= read -r SNAPSHOT < "$SUPPORT_SCRATCH/snapshot.raw" || true
if [[ -z "$SNAPSHOT" || "$SNAPSHOT" == unavailable ]]; then
    echo '无法生成经过字段筛选的报告，未创建 ZIP。请把这条错误消息回复到 Issue。' >&2
    exit 1
fi
support_run /bin/cp "$SUPPORT_SCRATCH/snapshot.raw" "$REPORT_DIR/environment.json"
support_run /bin/cp "$SUPPORT_DIR/REPORT-README.txt" "$REPORT_DIR/README.txt"
support_run /bin/date -u +%Y%m%dT%H%M%SZ > "$SUPPORT_SCRATCH/report-date"
IFS= read -r REPORT_DATE < "$SUPPORT_SCRATCH/report-date"
REPORT_NAME="Wattson-SystemBatteryIcon-$REPORT_DATE-$$.zip"
ARCHIVE="$SUPPORT_SCRATCH/$REPORT_NAME"
support_run /usr/bin/ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$REPORT_DIR" "$ARCHIVE"
support_run /usr/bin/unzip -t "$ARCHIVE" >/dev/null
SUPPORT_OUTPUT_PARTIAL="$OUTPUT_DIR/.$REPORT_NAME.partial.noindex"
support_run /bin/cp "$ARCHIVE" "$SUPPORT_OUTPUT_PARTIAL"
support_run /usr/bin/cmp -s "$ARCHIVE" "$SUPPORT_OUTPUT_PARTIAL"
support_run /bin/mv "$SUPPORT_OUTPUT_PARTIAL" "$OUTPUT_DIR/$REPORT_NAME"
SUPPORT_OUTPUT_PARTIAL=""
echo ''
echo "已保存 / Saved: $OUTPUT_DIR/$REPORT_NAME"
echo '请先解压检查 environment.json，再把 ZIP 拖到 GitHub Issue 回复框提交。'
echo '请同时说明：系统电池图标实际是否可见，以及刚才点击隐藏选项时的现象。'
