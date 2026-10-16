#!/usr/bin/perl
# Fixed read-only legacy-v4 socket requests; works with Wattson 4.3.6.
use strict;
use warnings;
use IO::Socket::UNIX;
use Socket qw(SOCK_STREAM);
use JSON::PP ();
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC alarm);

my $json = JSON::PP->new->utf8->canonical;
my %operations = map { $_ => 1 } qw(health getSystemBatteryIconHidden);
my %reasons = map { $_ => 1 } qw(userContextUnavailable preferenceSyncFailed
    preferenceMissing preferenceTypeUnsupported preferenceValueUnsupported preferenceWorkerFailed);
my %errors = map { $_ => 1 } ('unknown battery preference', 'request expired', 'rejected', 'malformed');

sub sanitize_response {
    my ($operation, $bytes) = @_;
    return { status => 'invalid-response' } unless $operations{$operation};
    my $raw = eval { $json->decode($bytes) };
    return { status => 'invalid-response' }
        unless ref($raw) eq 'HASH' && JSON::PP::is_bool($raw->{ok});
    my $result = { ok => $raw->{ok} };
    if ($raw->{ok}) {
        my $key = $operation eq 'health' ? 'health' : 'hidden';
        return { status => 'invalid-response' } unless JSON::PP::is_bool($raw->{$key});
        $result->{$key} = $raw->{$key};
        return { status => 'success', response => $result };
    }
    $result->{error} = !ref($raw->{error}) && defined($raw->{error}) && $errors{$raw->{error}}
        ? $raw->{error} : 'unrecognized-error';
    $result->{reason} = $raw->{reason}
        if !ref($raw->{reason}) && defined($raw->{reason}) && $reasons{$raw->{reason}};
    return { status => 'helper-error', response => $result };
}

sub probe {
    my ($operation) = @_;
    die "Unsupported operation\n" unless $operations{$operation};
    my $start = clock_gettime(CLOCK_MONOTONIC);
    my ($socket, $result);
    {
        # A single four-second budget covers connect, write and all response reads.
        local $SIG{ALRM} = sub { die "bounded-timeout\n" };
        local $SIG{PIPE} = 'IGNORE';
        my $completed = eval {
            alarm(4);
            $socket = IO::Socket::UNIX->new(Type => SOCK_STREAM, Peer => '/var/run/wattson-helper.sock');
            die "bounded-connect\n" unless $socket;
            my $request = $json->encode({ op => $operation, _wattsonProtocol => 4 }) . "\n";
            my $offset = 0;
            while ($offset < length($request)) {
                my $count = syswrite($socket, $request, length($request) - $offset, $offset);
                die "bounded-io\n" unless defined($count) && $count > 0;
                $offset += $count;
            }
            my $response = '';
            while (1) {
                my $count = sysread($socket, my $part, 4097 - length($response));
                die "bounded-io\n" unless defined($count);
                last if $count == 0;
                $response .= $part;
                if (length($response) > 4096) {
                    $result = { status => 'response-too-large' };
                    last;
                }
                last if index($response, "\n") >= 0;
            }
            $result ||= sanitize_response($operation, (split /\n/, $response, 2)[0] // '');
            1;
        };
        my $failure = $@;
        alarm(0);
        close($socket) if $socket;
        if (!$completed) {
            $result = { status => $failure eq "bounded-timeout\n" ? 'timeout'
                : $failure eq "bounded-connect\n" ? 'connection-failed' : 'io-error' };
        }
    }
    my $elapsed = int((clock_gettime(CLOCK_MONOTONIC) - $start) * 1000 + 0.5);
    return { operation => $operation, budgetMs => 4000, durationMs => $elapsed, %$result };
}

unless (caller) {
    die "Usage: socket_probe.pl health|getSystemBatteryIconHidden\n"
        unless @ARGV == 1 && $operations{$ARGV[0]};
    print $json->encode(probe($ARGV[0])) . "\n";
}
1;
