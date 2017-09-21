#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use Test::More;

use Doit;
use Doit::User 'as_user';

sub can_run_test {
    defined $ENV{SUDO_USER};
}

sub run {
    my %res = (
	SUDO_USER => $ENV{SUDO_USER}
    );

    as_user {
	chomp(my $uname = `id -nu`);
	chomp(my $homedir = `sh -c 'echo ~'`);

	$res{uname}   = $uname;
	$res{homedir} = $homedir;
    } $ENV{SUDO_USER};

    \%res;
}

return 1 if caller;

my $d = Doit->init;
my $sudo = eval { $d->do_sudo(sudo_opts => ['-n']) };
plan skip_all => "Cannot run sudo at all (not installed?)" if !$sudo;
my $res = eval { $sudo->call('can_run_test') };
plan skip_all => "Cannot run sudo password-less" if $@;
plan skip_all => "Cannot run test for other reasons" if !$res;

plan 'no_plan';

$res = $sudo->call('run');

is $res->{uname}, $res->{SUDO_USER};
is $res->{homedir}, $ENV{HOME};

## not needed anymore
#$sudo->exit;

__END__
