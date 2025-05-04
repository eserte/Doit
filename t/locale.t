#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use Test::More;

use Doit;

return 1 if caller();

plan 'no_plan';

my @warnings; $SIG{__WARN__} = sub { push @warnings, @_ };

require FindBin;
unshift @INC, $FindBin::RealBin;
require TestUtil;

my $doit = Doit->init;
$doit->add_component('locale');
ok $doit->can('locale_enable_locale'), "found method from component 'locale'";
SKIP: {
    my $test_count = 2;

    skip "Locale-adding code only active on CI systems", $test_count if !$ENV{GITHUB_ACTIONS};

    my $sudo = TestUtil::get_sudo($doit, info => \my %info);
    skip $info{error}, $test_count if !$sudo;

    my @try_locales = qw(de_DE.utf8 de_DE.UTF-8);
    my $res = $sudo->locale_enable_locale([@try_locales]);
    if ($res) {
	pass "de locale was added";
    } else {
	pass "de locale was already present";
    }

    {
	my $all_locales = $doit->qx({quiet=>1}, qw(locale -a));
	my $try_locales_rx = '(' . join('|', map { quotemeta $_ } @try_locales) . ')';
	ok grep { /$try_locales_rx/ } split /\n/, $all_locales;
    }

    ok !$sudo->locale_enable_locale([@try_locales]), '2nd install does nothing';

    ok !eval {
	$sudo->locale_enable_locale(['xx_XX.locale_does_not_exist', 'yy_YY.locale_does_not_exist']);
	1;
    }, 'fails with non-existing locales';
    if ($^O eq 'darwin') {
	like $@, qr{\QNo support for adding new locale 'xx_XX.locale_does_not_exist' on Mac OS X}, 'no local install on Mac OS X';
    } else {
	like $@, qr{Cannot find prepared locale 'xx_XX.locale_does_not_exist' in /etc/locale.gen}, 'first locale mentioned in error message';
    }
}

is_deeply \@warnings, [], 'no warnings';

__END__
