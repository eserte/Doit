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

    is $r->open2($^X, '-e', 'print scalar <STDIN>'), "", 'no instr -> empty input';

    is $r->open2({instr=>"some input\n"}, $^X, '-e', 'print scalar <STDIN>'), "some input\n", 'expected single-line result';

    is $r->open2({instr=>"first line\nsecond line\n"}, $^X, '-e', 'print join "", <STDIN>'), "first line\nsecond line\n", 'expected multi-line result';

    eval { $r->open2($^X, '-e', 'kill TERM => $$') };
    like $@, qr{^Command died with signal 15, without coredump};
    is $@->{signalnum}, 15;
    is $@->{coredump}, 'without';

    eval { $r->open2($^X, '-e', 'kill KILL => $$') };
    like $@, qr{^Command died with signal 9, without coredump};
    is $@->{signalnum}, 9;
    is $@->{coredump}, 'without';

    is $r->open2({quiet=>1}, $^X, '-e', '#nothing'), '', 'nothing returned; command is also quiet';

    is $r->info_open2($^X, '-e', 'print 42'), 42, 'info_open2 behaves as open2 in non-dry-run mode';
}

{
    local @ARGV = ('--dry-run');
    my $dry_run = Doit->init;
    is $dry_run->open2({instr=>"input"}, $^X, '-e', 'print scalar <STDIN>'), undef, 'no output in dry-run mode';
    is $dry_run->open2({instr=>"input",info=>1}, $^X, '-e', 'print scalar <STDIN>'), "input", 'info=>1: there is output in dry-run mode';
    is $dry_run->info_open2({instr=>"input"}, $^X, '-e', 'print scalar <STDIN>'), "input", 'info_open2 behaves like info=>1';
}


__END__
