#!/bin/bash
# Build the auditable source-only system battery icon support collector.
set -euo pipefail
umask 077
export COPYFILE_DISABLE=1
ROOT_DIR="$(cd "$(/usr/bin/dirname "$0")/.." && /bin/pwd)"
# shellcheck source=../Support/SystemBatteryIcon/lifecycle.sh
source "$ROOT_DIR/Support/SystemBatteryIcon/lifecycle.sh"
support_begin "$ROOT_DIR/.build/system-battery-support.noindex"
STAGING="$SUPPORT_SCRATCH/Wattson-SystemBatteryIcon-Support"
support_run /bin/mkdir "$STAGING"
for item in Collect-Wattson-SystemBatteryIcon.command collect.js socket_probe.pl lifecycle.sh README.md REPORT-README.txt; do
    support_run /bin/cp "$ROOT_DIR/Support/SystemBatteryIcon/$item" "$STAGING/$item"
done
support_run /bin/chmod 755 "$STAGING/Collect-Wattson-SystemBatteryIcon.command"
support_run /bin/bash -n "$STAGING/Collect-Wattson-SystemBatteryIcon.command" "$STAGING/lifecycle.sh"
support_run /usr/bin/perl -c "$STAGING/socket_probe.pl"
ARCHIVE_NAME=Wattson-SystemBatteryIcon-Support-v1.zip
support_run /usr/bin/ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$STAGING" "$SUPPORT_SCRATCH/$ARCHIVE_NAME"
support_run /usr/bin/unzip -t "$SUPPORT_SCRATCH/$ARCHIVE_NAME" >/dev/null
support_run /usr/bin/perl -MJSON::PP -MDigest::SHA - "$STAGING" "$SUPPORT_SCRATCH/$ARCHIVE_NAME" <<'PERL'
use strict;
use warnings;
my ($staging, $archive) = @ARGV;
sub digest {
    open my $file, '<', $_[0] or die "Cannot read packaged input\n";
    binmode $file;
    return Digest::SHA->new(256)->addfile($file)->hexdigest;
}
my $name = 'Wattson-SystemBatteryIcon-Support-v1.zip';
my $sha = digest($archive);
(my $base = $archive) =~ s/\.zip$//;
open my $checksum, '>', "$base.sha256" or die "Cannot write checksum\n";
print $checksum "$sha  $name\n";
close $checksum or die "Cannot finish checksum\n";
my %files;
for my $item (qw(Collect-Wattson-SystemBatteryIcon.command collect.js socket_probe.pl lifecycle.sh README.md REPORT-README.txt)) {
    $files{$item} = digest("$staging/$item");
}
open my $metadata, '>', "$base.metadata.json" or die "Cannot write metadata\n";
print $metadata JSON::PP->new->canonical->pretty->encode({ schema => 1, bundleVersion => 1,
    archive => $name, sha256 => $sha, files => \%files });
close $metadata or die "Cannot finish metadata\n";
PERL
DIST_DIR="$ROOT_DIR/dist/support"
support_run /bin/mkdir -p "$DIST_DIR"
for suffix in zip sha256 metadata.json; do
    support_run /bin/mv "$SUPPORT_SCRATCH/Wattson-SystemBatteryIcon-Support-v1.$suffix" "$DIST_DIR/Wattson-SystemBatteryIcon-Support-v1.$suffix"
done
echo "Built: $DIST_DIR/$ARCHIVE_NAME"
