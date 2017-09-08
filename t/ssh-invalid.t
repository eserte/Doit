#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use Doit;

return 1 if caller;

require Test::More;
Test::More->import('no_plan');

my @std_master_opts = qw(-oPasswordAuthentication=no -oBatchMode=yes);

my $d = Doit->init;

{
    my $ssh = eval { $d->do_ssh_connect('host.invalid', master_opts => [@std_master_opts]) };
    ok(!$ssh, 'Failed to connect to invalid host as expected');
}

{
    my $ssh = eval { $d->do_ssh_connect('invalid.user.just.for.testing.Doit.pm@localhost', master_opts => [@std_master_opts]) };
    ok(!$ssh, 'Failed to connect to localhost with invalid user');
}

__END__
