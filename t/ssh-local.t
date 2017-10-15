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

sub stdout_test {
    print "This goes to STDOUT\n";
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

# XXX currently the output is not visible ---
# to work around this problem $|=1 has to be set in the function
# This should be done automatically.
# Another possibility: call $ssh->exit. But this would mean that
# the output only appears at the exit() call, not before.
# Also, this should be a proper test, e.g. using Capture::Tiny
$ssh->call_with_runner('stdout_test');

is($ssh->exit, 'bye-bye', 'exit called'); # XXX hmmm, should this really return "bye-bye"?

eval { $ssh->system($^X, '-e', 'exit 0') };
isnt($@, '', 'calling on ssh after exit');

__END__
