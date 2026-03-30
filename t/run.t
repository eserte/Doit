#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use FindBin;
use lib $FindBin::RealBin;

use Test::More;

plan skip_all => "no IPC::Run installed (highly recommended, but optional)" if !eval { require IPC::Run; 1 };
plan 'no_plan';

use Doit;

use TestUtil qw(signal_kill_num);
my $KILL = signal_kill_num;
my $KILLrx = qr{$KILL};

my $enable_coredump_tests = $ENV{GITHUB_ACTIONS} || $ENV{DOIT_TEST_WITH_COREDUMP};

my $r = Doit->init;

is $r->run($^X, '-e', 'exit 0'), 1;
pass 'no exception';

eval { $r->run($^X, '-e', 'exit 1') };
like $@, qr{^Command exited with exit code 1};
is $@->{exitcode}, 1;

SKIP: {
    skip "kill TERM not supported on Windows' system()", 3 if $^O eq 'MSWin32';
    eval { $r->run([$^X, '-e', 'kill TERM => $$']) };
    like $@, qr{^Command died with signal 15, without coredump};
    is $@->{signalnum}, 15;
    is $@->{coredump}, 'without';
}

eval { $r->run([$^X, '-e', 'kill KILL => $$']) };
if ($^O eq 'MSWin32') {
    # There does not seem to be any signal handling on Windows
    # --- exit(9) and kill KILL is indistinguishable here.
    like $@, qr{^Command exited with exit code $KILLrx};
} else {
    like $@, qr{^Command died with signal $KILLrx, without coredump};
    is $@->{signalnum}, $KILL;
    is $@->{coredump}, 'without';
}

SKIP: {
    my $no_tests = 3;
    skip "Coredump tests unreliable and not enabled everywhere", $no_tests
	if !$enable_coredump_tests;
    skip "No BSD::Resource available", $no_tests
	if !eval { require BSD::Resource; 1 };
    skip "coredumps disabled", $no_tests
	if BSD::Resource::getrlimit(BSD::Resource::RLIMIT_CORE()) < 4096; # minimum of 4k needed on linux to actually do coredumps
    eval { $r->run([$^X, '-e', 'kill ABRT => $$']) };
    like $@, qr{^Command died with signal 6, with coredump}, 'error message with coredump';
    is $@->{signalnum}, 6, 'expected signalnum';
    is $@->{coredump}, 'with', 'expected coredump value ("with")';
}

{
    require File::Temp;
    my $tempdir = File::Temp::tempdir('doit_XXXXXXXX', TMPDIR => 1, CLEANUP => 1);

    local @ARGV = ('--dry-run');
    my $dry_run = Doit->init;

    {
	my $no_create_file = "$tempdir/should_never_happen";
	is $dry_run->run([$^X, '-e', 'open my $fh, ">", $ARGV[0] or die $!', $no_create_file]), 1, 'returns 1 in dry-run mode';
	ok ! -e $no_create_file, 'dry-run mode, no file was created';
    }

    {
	my $create_file = "$tempdir/should_happen";
	is $dry_run->info_run([$^X, '-e', 'open my $fh, ">", $ARGV[0] or die $!', $create_file]), 1, 'returns 1 as info_run call';
	ok -e $create_file, 'info_run runs even in dry-run mode';
	$r->unlink($create_file);
    }

    {
	my $create_file = "$tempdir/should_happen";
	is $dry_run->run({info=>1}, [$^X, '-e', 'open my $fh, ">", $ARGV[0] or die $!', $create_file]), 1, 'returns 1 as run call with info=>1 option';
	ok -e $create_file, 'run with info=>1 option runs even in dry-run mode';
	$r->unlink($create_file);
    }
}

__END__
