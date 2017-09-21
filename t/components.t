#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use Test::More;

use Doit;

sub check_deb_component {
    my $d = shift;
    !!$d->can('deb_missing_packages');
}

sub check_git_component {
    my $d = shift;
    !!$d->can('git_repo_update');
}

return 1 if caller;

plan 'no_plan';

my $d = Doit->init;
$d->add_component('git');
$d->add_component('deb');

ok $d->call_with_runner('check_deb_component'), 'available deb component locally';
ok $d->call_with_runner('check_git_component'), 'available git component locally';

SKIP: {
    my $number_of_tests = 2;
    my $sudo = eval { $d->do_sudo(sudo_opts => ['-n'], debug => 0) };
    skip "Cannot run sudo (not available?)", $number_of_tests
	if !$sudo;
    my $res = eval { $sudo->system('true'); 1 };
    skip "Cannot run sudo (password less)", $number_of_tests
	if !$res;

    ok $sudo->call_with_runner('check_deb_component'), 'available deb component through sudo';
    ok $sudo->call_with_runner('check_git_component'), 'available git component through sudo';
}

__END__
