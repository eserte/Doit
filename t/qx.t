#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use Test::More;

plan skip_all => "Signals are problematic on Windows" if $^O eq 'MSWin32';
plan 'no_plan';

use Doit;

{
    my $r = Doit->init;

    is $r->qx($^X, '-e', 'print 42'), 42, 'expected single-line result';

    is $r->qx($^X, '-e', 'print "first line\nsecond line\n"'), "first line\nsecond line\n", 'expected mulit-line result';

    eval { $r->qx($^X, '-e', 'kill TERM => $$') };
    like $@, qr{^Command died with signal 15, without coredump};
    is $@->{signalnum}, 15;
    is $@->{coredump}, 'without';

    eval { $r->qx($^X, '-e', 'kill KILL => $$') };
    like $@, qr{^Command died with signal 9, without coredump};
    is $@->{signalnum}, 9;
    is $@->{coredump}, 'without';

    is $r->qx({quiet=>1}, $^X, '-e', '#nothing'), '', 'nothing returned; command is also quiet';

    is $r->info_qx($^X, '-e', 'print 42'), 42, 'info_qx behaves as qx in non-dry-run mode';

    ok !eval { $r->info_qx($^X, '-e', 'exit 1'); 1 };
    like $@, qr{qx command '.* -e exit 1' failed: Command exited with exit code 1 at .* line \d+}, 'verbose error message with failed info_qx command';

    {
	my %status;
	is $r->qx({statusref => \%status}, $^X, '-e', 'print STDOUT "some output\n"; exit 0'), "some output\n";
	is $status{exitcode}, 0, 'status reference filled, exit code as expected (success)';
    }

    {
	my %status;
	is $r->qx({statusref => \%status}, $^X, '-e', 'print STDOUT "some output\n"; exit 1'), "some output\n";
	is $status{exitcode}, 1, 'status reference filled, exit code as expected (failure)';
    }
}

{
    local @ARGV = ('--dry-run');
    my $dry_run = Doit->init;
    is $dry_run->qx($^X, '-e', 'print 42'), undef, 'no output in dry-run mode';
    is $dry_run->qx({info=>1}, $^X, '-e', 'print 42'), 42, 'info=>1: there is output in dry-run mode';
    is $dry_run->info_qx($^X, '-e', 'print 42'), 42, 'info_qx behaves like info=>1';
}


__END__