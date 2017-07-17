#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use Test::More;

use Doit;

return 1 if caller();

plan skip_all => "Only active on travis"
    if !$ENV{TRAVIS};
plan 'no_plan';

my @try_locales = qw(de_DE.utf8 de_DE.UTF-8);

my $d = Doit->init;
$d->add_component('locale');
pass "added component 'locale'";

{
    my $sudo = $d->do_sudo(sudo_opts => ['-n']);
    my $res = $sudo->locale_enable_locale([@try_locales]);
    if ($res) {
	pass "de locale was added";
    } else {
	pass "de locale was already present";
    }
    $sudo->exit;

    {
	my $all_locales = $d->qx({quiet=>1}, qw(locale -a));
	my $try_locales_rx = '(' . join('|', map { quotemeta $_ } @try_locales) . ')';
	ok grep { /$try_locales_rx/ } split /\n/, $all_locales;
    }
}

__END__
