#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use Test::More;

use Doit;
use Doit::Extcmd qw(is_in_path);

sub run {
    my $d = shift;
    chomp(my $res = `id -u`);
    $res;
}

sub pwinfo {
    getpwuid($<);
}

return 1 if caller;

if (!is_in_path('sudo')) {
    plan skip_all => 'git not in PATH';
}

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
