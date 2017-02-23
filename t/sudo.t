#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use Test::More;

use Doit;

sub run {
    my $d = shift;
    chomp(my $res = `id -u`);
    $res;
}

sub pwinfo {
    getpwuid($<);
}

return 1 if caller;

my $d = Doit->init;
my $sudo = $d->do_sudo(sudo_opts => ['-n']);
my $res = eval { $sudo->call('run') };

plan skip_all => "Cannot run sudo password-less" if $@;
plan 'no_plan';

isa_ok $sudo, 'Doit::Sudo';
is $res, 0, 'switched to uid=0';

my(@pwinfo) = $sudo->call('pwinfo');
is $pwinfo[0], 'root';

$sudo->exit;

__END__
