#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use Doit;

return 1 if caller;

require Test::More;
Test::More->import;

my $d = Doit->init;
my $ssh = eval { $d->do_ssh_connect('localhost', debug => 0, master_opts => [qw(-oPasswordAuthentication=no -oBatchMode=yes)]) };
if (!$ssh) {
    plan(skip_all => "Cannot do ssh localhost: $@");
}
isa_ok($ssh, 'Doit::SSH');
plan('no_plan');
my $ret = $ssh->info_qx('perl', '-e', 'print "yes\n"');
is($ret, "yes\n", 'run command via local ssh connection');

__END__
