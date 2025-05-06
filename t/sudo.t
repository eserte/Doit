#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use Getopt::Long;
use Test::More;

use Doit;

sub get_id {
    chomp(my $res = `id -u`);
    $res;
}

sub pwinfo {
    getpwuid($<);
}

sub envinfo { \%ENV }

sub stdout_test {
    print "This goes to STDOUT\n";
    4711;
}

sub stderr_test {
    print STDERR "This goes to STDERR\n";
    314;
}

sub expected_home_env ($$) {
    my($got_home, $sudo_username) = @_;
    # depending on sudoers HOME is kept or set to the sudo user's HOME, so accept both
    my $sudo_homedir = (getpwnam($sudo_username))[7];
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    like $got_home, qr{^(\Q$ENV{HOME}\E|\Q$sudo_homedir\E)$}, 'expected homedir';
}

return 1 if caller;

require FindBin;
{ no warnings 'once'; push @INC, $FindBin::RealBin; }
require TestUtil;

my $other_user;
my $debug = $ENV{DOIT_TRACE}; # XXX maybe use just DOIT_TRACE?
GetOptions(
	   "other-user=s" => \$other_user,
	   "debug" => \$debug,
	  )
    or die "usage: $0 [--other-user username] [--debug]\n";

my $d = Doit->init;

if (!$d->which('sudo')) {
    plan skip_all => 'sudo not in PATH';
}

plan 'no_plan';

my $my_username = ($d->call('pwinfo'))[0];
for my $def (
    (defined $my_username && $my_username ne '' ? [$my_username, $<] : ()),
    ['root', 0],
) {
    my($username, $userid) = @$def;
 SKIP: {
	my @do_sudo_opts = ($username ne 'root' ? (sudo_opts => ['-u', $username]) : ());
 
	my %info;
	my $sudo = TestUtil::get_sudo(
	    $d,
	    info => \%info,
	    debug => $debug,
	    @do_sudo_opts,
	);
	skip "Cannot test sudo with user $username: $info{error}" if !$sudo;

	is ref $sudo, 'Doit::Sudo', "got Doit::Sudo object for username $username";

	my $res = $sudo->call('get_id');
	is $res, $userid, "switched to uid=$userid";

	{
	    my(@pwinfo) = $sudo->call('pwinfo');
	    is $pwinfo[0], $username, 'expected username from getpwuid call';
	    my $envinfo = $sudo->call('envinfo');
	    expected_home_env($envinfo->{HOME}, $username);
	    is $envinfo->{DOIT_IN_REMOTE}, 1, 'DOIT_IN_REMOTE env var set';
	}

	is $sudo->call('stdout_test'), 4711, 'expected stdout output';
	is $sudo->call('stderr_test'), 314,  'expected stderr output';

	{
	    my $res = $sudo->qx({quiet=>1}, 'perl', '-e', 'print "STDOUT without newline"');
	    is $res, 'STDOUT without newline', 'stdout without newline';
	}

	{
	    my $sudo2 = $d->do_sudo(@do_sudo_opts, debug => $debug);
	    isa_ok $sudo2, 'Doit::Sudo';

	    # try explicit exit
	    $sudo->exit;
	    pass 'exited once';
	    # another exit is a no-op
	    $sudo->exit;
	    pass 'exited twice';

	    eval { $sudo->system($^X, '-e', 'exit 0') };
	    isnt $@, '', 'calling on sudo after exit';

	    # and the DESTROY after should not error, too
	}

	if ($username eq 'root') {
	SKIP: {
		skip "--other-user option not set", 1
		    if !defined $other_user;
		# -H (--set-home) may or may not be necessary
		my $sudo = $d->do_sudo(sudo_opts => ['-n', '-u', $other_user, '-H'], debug => $debug);
		my $res = eval { $sudo->call('get_id') };
		skip "Cannot run sudo -u password-less",1
		    if $@;

		my(@pwinfo) = $sudo->call('pwinfo');
		is $pwinfo[0], $other_user;
		my $envinfo = $sudo->call('envinfo');
		expected_home_env($envinfo->{HOME}, $other_user);
		is $envinfo->{DOIT_IN_REMOTE}, 1, 'DOIT_IN_REMOTE env var set';
	    }
	}

	{
	    local $SIG{ALRM} = sub { die "Timeout" };
	    local $TODO;
	    $TODO = "Known to possible hang on darwin" if $^O eq 'darwin';
	    my $hello_world;
	    alarm(20);
	    eval {
		chomp($hello_world = $d->info_qx($^X, '-MDoit', '-e', 'Doit->init->do_sudo(sudo_opts => [q(-u), $ARGV[0]], debug => $ARGV[1])->system(qw(echo Hello world))', '--', $username, !!$debug));
	    };
	    my $err = $@;
	    alarm(0);
	    is $err, '', 'No timeout';
	    is $hello_world, 'Hello world', 'Running do_sudo in a perl oneliner works';
	}
    }

    {
	# check if the terminal is still or again sane
	require POSIX;
	my $file_num = fileno(\*STDIN);
	if (POSIX::isatty($file_num)) {
	    my $termios = POSIX::Termios->new;
	    $termios->getattr($file_num);
	    ok $termios->getiflag & POSIX::BRKINT(), 'brkint is still/again set';
	    ok $termios->getiflag & POSIX::ICRNL(), 'icrnl is still/again set';
	}
    }
}

__END__
