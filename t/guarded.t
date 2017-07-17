#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use Test::More 'no_plan';
use Doit;

my $d = Doit->init;
$d->add_component('guarded');

{
    my $var = 0;
    my $called = 0;

    $d->guarded_step(
	"var to zero",
	ensure => sub { $var == 1 },
	using  => sub { $var = 1; $called++  },
    );
    is $var, 1;
    is $called, 1, '1st time "using" called';

    $d->guarded_step(
	"var to zero (is already)",
	ensure => sub { $var == 1 },
	using  => sub { $var = 1; $called++ },
    );
    is $var, 1;
    is $called, 1, '2nd time "using" not called';
}

SKIP: {
    skip "Need IPC::Run", 1 if !$d->can_ipc_run;

    my $var = 0;
    $d->guarded_step(
	"extern command",
	ensure => sub { $var == 3.14 },
	using  => sub {
	    my $d = shift;
	    $d->run(['perl', '-e', 'print 3.14'], '>', \$var);
	},
    );
    is $var, 3.14, 'Doit method successfully run';
}

{
    my $var = 0;
    eval {
	$d->guarded_step(
	    "will fail",
	    ensure => sub { $var == 1 },
	    using  => sub { $var = 2 },
	);
    };
    like $@, qr{ERROR:.* 'ensure' block for 'will fail' still fails after running the 'using' block};
}

local @ARGV = ('--dry-run');
$d = Doit->init;

{
    my $var = 0;
    my $called = 0;

    $d->guarded_step(
	"var to zero",
	ensure => sub { $var == 1 },
	using  => sub { $var = 1; $called++  },
    );
    is $var, 0, 'not changed, dry-run';
    is $called, 0, 'not called, dry-run';
}