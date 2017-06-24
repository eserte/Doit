#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use Test::More;

#plan skip_all => "Only active on travis"
#    if !$ENV{TRAVIS};
plan 'no_plan';

use Doit;

my $d = Doit->init;
$d->add_component('locale');
pass "added component 'locale'";

my $linuxcodename;
if ($^O eq 'linux') {
    chomp($linuxcodename = `lsb_release -cs`);
}

SKIP: {
    skip "Does not have /etc/locale.gen", 1
	if defined $linuxcodename && $linuxcodename eq 'precise';

    my $res = $d->locale_enable_locale(['de_DE.utf8', 'de_DE.UTF-8']);
    if ($res) {
	pass "de locale was added";
    } else {
	pass "de locale was already present";
    }

 SKIP: {
	skip "Does not have IPC::Run", 1
	    if !$d->can_ipc_run;
	$d->run(['locale', '-a'], '>', \my $all_locales);
	ok grep { /de_DE\.(utf8|UTF-8)/ } split /\n/, $all_locales;
    }
}

__END__
