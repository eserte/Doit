#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use Test::More;

use Doit;

use Sys::Hostname; plan skip_all => 1; # XXX "not on travis (password less sudo needed)" if !$ENV{TRAVIS}; # XXX need better checks!

plan 'no_plan';

my $d = Doit->init;
$d->add_component('git');
$d->add_component('deb');

my $s = $d->do_sudo;
ok $s->system("true");

__END__
