#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use Cwd 'getcwd';
use Doit;
use File::Temp qw(tempdir);

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
	DOIT_IN_REMOTE    => $ENV{DOIT_IN_REMOTE},
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
is($env->{DOIT_IN_REMOTE}, 1, 'DOIT_IN_REMOTE env set');

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

SKIP: {
    Test::More::skip("Symlinks on Windows?", 1) if $^O eq 'MSWin32';

    # Do a symlink test
    my $dir = tempdir("doit_XXXXXXXX", TMPDIR => 1, CLEANUP => 1);
    $d->write_binary("$dir/test-doit.pl", <<'EOF');
use Doit;
return 1 if caller;
my $doit = Doit->init;
my $ssh = $doit->do_ssh_connect((defined $ENV{USER} ? $ENV{USER}.'@' : '') . 'localhost', debug => 0, master_opts => [qw(-oPasswordAuthentication=no -oBatchMode=yes)]);
my $ret = $ssh->info_qx('perl', '-e', 'print "yes\n"');
print $ret;
EOF
    $d->chmod(0755, "$dir/test-doit.pl");
    $d->symlink("$dir/test-doit.pl", "$dir/test-symlink.pl");
    my $ret = $d->info_qx($^X, "$dir/test-symlink.pl");
    Test::More::is($ret, "yes\n");
}

__END__
