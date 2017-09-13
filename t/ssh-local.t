#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use Cwd 'getcwd';
use Doit;

sub environment {
    my($doit) = @_;
    require FindBin;
    my $original_realbin = $FindBin::RealBin;
    FindBin->again;
    my $refreshed_realbin = $FindBin::RealBin;
    return {
	cwd               => getcwd,
	original_realbin  => $original_realbin,
	refreshed_realbin => $refreshed_realbin,
    };
}

return 1 if caller;

require Test::More;
Test::More->import;

my $d = Doit->init;
my $ssh = eval { $d->do_ssh_connect((defined $ENV{USER} ? $ENV{USER}.'@' : '') . 'localhost', debug => 0, master_opts => [qw(-oPasswordAuthentication=no -oBatchMode=yes)]) };
if (!$ssh) {
    plan(skip_all => "Cannot do ssh localhost: $@");
}
isa_ok($ssh, 'Doit::SSH');
plan('no_plan');
my $ret = $ssh->info_qx('perl', '-e', 'print "yes\n"');
is($ret, "yes\n", 'run command via local ssh connection');
my $env = $ssh->call_with_runner('environment');
is($env->{cwd}, $ENV{HOME}, 'expected cwd is current home directory');
## XXX Actually it's unclear what $FindBin::RealBin should return here
#is($env->{original_realbin}, '???');
#is($env->{refreshed_realbin}, '???');

__END__
