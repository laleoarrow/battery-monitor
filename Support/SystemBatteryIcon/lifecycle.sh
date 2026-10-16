#!/bin/bash
# Shared ownership of this support bundle's scratch directory and child processes.
SUPPORT_SCRATCH=""
SUPPORT_SCRATCH_ROOT=""
SUPPORT_ROOT_CREATED=0
SUPPORT_OUTPUT_PARTIAL=""
SUPPORT_ALLOCATION=""
SUPPORT_TOTAL_SECONDS=45
SUPPORT_STAGE_SECONDS=10
SUPPORT_DEADLINE=""
SUPPORT_DEFER_SIGNALS=0
SUPPORT_PENDING_SIGNAL=0
# A sentinel keeps macOS's Bash 3.2 compatible with `set -u` on empty arrays.
SUPPORT_CHILDREN=("")

support_validate_path() {
    case "$1" in
        *$'\n'*|*$'\r'*) echo 'Paths containing line breaks are not supported.' >&2; return 2 ;;
    esac
}

# Validate the whole reply before publishing a path to an owner or caller.
support_read_path() {
    local candidate remainder
    {
        IFS= read -r candidate || return 1
        if IFS= read -r remainder || [[ -n "$remainder" ]]; then return 2; fi
    } < "$1"
    support_validate_path "$candidate" || return $?
    [[ -n "$candidate" ]] || return 1
    printf '%s' "$candidate"
}

support_signal() {
    if [[ "$SUPPORT_DEFER_SIGNALS" -gt 0 ]]; then
        [[ "$SUPPORT_PENDING_SIGNAL" != 0 ]] || SUPPORT_PENDING_SIGNAL=$1
    else
        exit "$1"
    fi
}

support_resume_signals() {
    SUPPORT_DEFER_SIGNALS=$((SUPPORT_DEFER_SIGNALS - 1))
    if [[ "$SUPPORT_DEFER_SIGNALS" == 0 && "$SUPPORT_PENDING_SIGNAL" != 0 ]]; then
        exit "$SUPPORT_PENDING_SIGNAL"
    fi
}

support_cleanup() {
    local status=$?
    trap - EXIT
    trap '' HUP INT TERM
    local pid
    for pid in "${SUPPORT_CHILDREN[@]}"; do
        [[ -n "$pid" ]] || continue
        kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    done
    # Give the supervisor time to reap its direct child; the group fallback
    # also catches descendants if the supervisor could not finish.
    if [[ ${#SUPPORT_CHILDREN[@]} -gt 1 ]]; then /bin/sleep 0.5; fi
    for pid in "${SUPPORT_CHILDREN[@]}"; do
        [[ -n "$pid" ]] || continue
        kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    SUPPORT_CHILDREN=("")
    SUPPORT_DEFER_SIGNALS=0
    SUPPORT_PENDING_SIGNAL=0
    # Cleanup has its own five-second grace, even after collection timed out.
    SUPPORT_DEADLINE=$(/usr/bin/perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e \
        'print clock_gettime(CLOCK_MONOTONIC) + 5')
    if [[ -n "$SUPPORT_SCRATCH" ]]; then
        support_run_for 2 /bin/rm -rf -- "$SUPPORT_SCRATCH" || status=1
    fi
    if [[ -n "$SUPPORT_OUTPUT_PARTIAL" ]]; then
        support_run_for 2 /bin/rm -f -- "$SUPPORT_OUTPUT_PARTIAL" || status=1
    fi
    if [[ -n "$SUPPORT_ALLOCATION" ]]; then
        support_run_for 2 /bin/rm -f -- "$SUPPORT_ALLOCATION" || status=1
    fi
    if [[ "$SUPPORT_ROOT_CREATED" == 1 ]]; then
        support_run_for 2 /bin/rmdir -- "$SUPPORT_SCRATCH_ROOT" 2>/dev/null || true
    fi
    exit "$status"
}

support_begin() {
    support_validate_path "$1" || return $?
    SUPPORT_SCRATCH_ROOT=$1
    trap support_cleanup EXIT
    trap 'support_signal 129' HUP
    trap 'support_signal 130' INT
    trap 'support_signal 143' TERM
    SUPPORT_DEADLINE=$(/usr/bin/perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e \
        'print clock_gettime(CLOCK_MONOTONIC) + $ARGV[0]' "$SUPPORT_TOTAL_SECONDS")
    if [[ ! -d "$SUPPORT_SCRATCH_ROOT" ]]; then
        SUPPORT_ROOT_CREATED=1
        support_run /bin/mkdir -p -- "$SUPPORT_SCRATCH_ROOT"
    fi
    # Retain ownership across allocation and reading its returned path.
    SUPPORT_ALLOCATION="$SUPPORT_SCRATCH_ROOT/.allocation.$$.$RANDOM"
    SUPPORT_DEFER_SIGNALS=$((SUPPORT_DEFER_SIGNALS + 1))
    local allocation_status=0 allocated=""
    support_run /usr/bin/mktemp -d "$SUPPORT_SCRATCH_ROOT/run.XXXXXX" > "$SUPPORT_ALLOCATION" || allocation_status=$?
    allocated=$(support_read_path "$SUPPORT_ALLOCATION") || {
        [[ "$allocation_status" != 0 ]] || allocation_status=1
    }
    case "$allocated" in
        "$SUPPORT_SCRATCH_ROOT"/run.??????) SUPPORT_SCRATCH=$allocated ;;
        *) [[ "$allocation_status" != 0 ]] || allocation_status=1 ;;
    esac
    support_resume_signals
    [[ "$allocation_status" == 0 ]] || return "$allocation_status"
    [[ -n "$SUPPORT_SCRATCH" ]] || return 1
    support_run /bin/rm -f -- "$SUPPORT_ALLOCATION"
    SUPPORT_ALLOCATION=""
}

support_track() {
    SUPPORT_CHILDREN+=("$1")
}

support_forget() {
    local remaining=("") pid
    for pid in "${SUPPORT_CHILDREN[@]}"; do
        [[ -n "$pid" ]] || continue
        [[ "$pid" == "$1" ]] || remaining+=("$pid")
    done
    SUPPORT_CHILDREN=("${remaining[@]}")
}

support_run() {
    support_run_for "$SUPPORT_STAGE_SECONDS" "$@"
}

# One supervisor per stage; no external polling sleeps. Every stage shares
# the same monotonic overall deadline, including archive and output work.
support_run_for() {
    local seconds=$1
    shift
    SUPPORT_DEFER_SIGNALS=$((SUPPORT_DEFER_SIGNALS + 1))
    /usr/bin/perl -e '
use strict;
use warnings;
use POSIX qw(WNOHANG setpgid);
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC sleep);
my ($overall, $limit, @command) = @ARGV;
my $now = clock_gettime(CLOCK_MONOTONIC);
my $deadline = $now + $limit < $overall ? $now + $limit : $overall;
exit 124 if $deadline <= $now;
my $signal = 0;
$SIG{HUP} = sub { $signal ||= 129 };
$SIG{INT} = sub { $signal ||= 130 };
$SIG{TERM} = sub { $signal ||= 143 };
setpgid(0, 0) == 0 or die "Cannot isolate support stage\n";
my $child = fork();
die "Cannot start support stage\n" unless defined $child;
if (!$child) {
    $SIG{$_} = "DEFAULT" for qw(HUP INT TERM);
    exec { $command[0] } @command;
    exit 127;
}
sub stop_child {
    $SIG{$_} = "IGNORE" for qw(HUP INT TERM);
    kill "TERM", -$$;
    sleep(0.15);
    kill "KILL", $child;
    waitpid($child, 0);
}
while (1) {
    if ($signal || clock_gettime(CLOCK_MONOTONIC) >= $deadline) {
        stop_child();
        exit($signal || 124);
    }
    my $finished = waitpid($child, WNOHANG);
    if ($finished == $child) {
        my $status = $?;
        $SIG{$_} = "IGNORE" for qw(HUP INT TERM);
        kill "TERM", -$$;
        exit(($status & 127) ? 128 + ($status & 127) : $status >> 8);
    }
    if ($finished < 0) {
        next if $!{EINTR};
        stop_child();
        die "Cannot wait for support stage\n";
    }
    sleep(0.02);
}
' "$SUPPORT_DEADLINE" "$seconds" "$@" <&0 &
    local pid=$! status=0
    support_track "$pid"
    support_resume_signals
    while true; do
        wait "$pid" && status=0 || status=$?
        # A deferred signal interrupts Bash wait without finishing the child.
        kill -0 "$pid" 2>/dev/null || break
    done
    # The supervisor PID is also its process-group ID, established before
    # fork. Clean descendants even after a normally exiting direct command.
    kill -KILL -- "-$pid" 2>/dev/null || true
    support_forget "$pid"
    return "$status"
}
