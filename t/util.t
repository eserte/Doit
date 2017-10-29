#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use Cwd 'getcwd';
use Doit;
use Doit::Util;
use File::Temp qw(tempdir);
use Test::More;

sub run_copy_stat {
    my($doit, $source, $target) = @_;
    copy_stat($source, $target);
}

return 1 if caller;

require FindBin;
{ no warnings 'once'; push @INC, $FindBin::RealBin; }
require TestUtil;

plan 'no_plan';

{
    my $change_dir = $^O eq 'MSWin32' ? 'C:/' : '/';
    my $orig_dir = getcwd;
    in_directory {
	is getcwd, $change_dir, "directory was changed to $change_dir";
    } $change_dir;
    is getcwd, $orig_dir, "directory was restored to $orig_dir";

    eval {
	in_directory {
	    die "A failure happened";
	} $change_dir;
	fail "This should never happen";
    };
    like $@, qr{^A failure happened}, 'exception was propagated';
    is getcwd, $orig_dir, "directory was restored to $orig_dir, in spite of an exception";

    eval {
	in_directory {
	    fail "This should never happen";
	} "$orig_dir/this/directory/does/not/exist";
    };
    like $@, qr{Can't chdir to .*this/directory/does/not/exist}, 'non-existent directory';
    is getcwd, $orig_dir, "directory was never changed";
}

SKIP: {
    skip "Cannot remove active directory in MSWin32", 1
	if $^O eq 'MSWin32';
    my $orig_dir = getcwd;
    my $tempdir;
    $tempdir = tempdir(TMPDIR => 1, CLEANUP => 1);
    in_directory {
	in_directory {
	    my $doit = Doit->init;
	    $doit->rmdir($tempdir);
	} "/";
	is getcwd, "/", 'still in /, temporary directory does not exist anymore';
    } $tempdir;
    is getcwd, $orig_dir, 'everything\'s restored';

    $tempdir = tempdir(TMPDIR => 1, CLEANUP => 1);
    in_directory {
	mkdir "$tempdir/another_dir" or die "Cannot create temporary directory: $!";
	chdir "$tempdir/another_dir" or die "Cannot chdir: $!";
	rmdir "$tempdir/another_dir" or die "Cannot remove directory: $!";
	in_directory {
	    # do nothing, but a warning
	    # "WARN: No known current working directory"
	    # should appear
	} "/";
	is getcwd, "/", 'still in /, we had no known current working directory before';
    } $tempdir;
    is getcwd, $orig_dir, 'everything\'s restored again';
}

{
    my $scope_cleanup_one_called;
    my $scope_cleanup_two_called;

    {
	my $sc = new_scope_cleanup { $scope_cleanup_one_called = 1 }; # may be called with or without sub
	$sc->add_scope_cleanup(sub { $scope_cleanup_two_called = 1 });
    }

    ok $scope_cleanup_one_called, 'callback created with new_scope_cleanup called';
    ok $scope_cleanup_two_called, 'callback created with add_scope_cleanup called';
}

{
    my $scope_cleanup_two_called;
    $@ = '';
    {
	my $sc = new_scope_cleanup sub { die "cleanup callback dies" };
	$sc->add_scope_cleanup(sub { $scope_cleanup_two_called = 1 });
    };
    like $@, qr{cleanup callback dies}, 'failed scope cleanup';
    ok !$scope_cleanup_two_called, '2nd callback not called';
}

{
    my $doit = Doit->init;
    my %sudo_info;
    my $sudo = TestUtil::get_sudo($doit, info => \%sudo_info); # must run in this directory

    my $tempdir = tempdir(TMPDIR => 1, CLEANUP => 1);
    in_directory {
	$doit->create_file_if_nonexisting('source');
	$doit->create_file_if_nonexisting('target');

	my @stat = stat('source');

	$doit->chmod(0600, 'source');
	copy_stat('source', 'target');
	is(((stat('target'))[2] & 07777), 0600, 'preserving mode');

	$stat[2] = 0640;
	copy_stat(\@stat, 'target');
	is(((stat('target'))[2] & 07777), 0640, 'preserving mode using stat array');

	$doit->utime(86400,86400,'source');
	copy_stat('source', 'target');
	is((stat('target'))[8], 86400, 'preserving atime');
	is((stat('target'))[9], 86400, 'preserving mtime');

	$stat[8] = $stat[9] = 86400*2;
	copy_stat(\@stat, 'target');
	is((stat('target'))[8], 86400*2, 'preserving atime using stat array');
	is((stat('target'))[9], 86400*2, 'preserving mtime using stat array');

	# Must be last in this block --- source+target are deleted
    SKIP: {
	    skip "Can't sudo: $sudo_info{error}", 2 if !$sudo;
	    $sudo->chown(0,0,"$tempdir/source");
	    $sudo->call_with_runner('run_copy_stat', "$tempdir/source", "$tempdir/target"); # NOTE: directory change does not apply to sudo context XXX would be nicer if $sudo->copy_stat could be used
	    is((stat('target'))[4], 0, 'preserving owner');
	    is((stat('target'))[5], 0, 'preserving group');
	    $sudo->unlink(qw(source target));
	}
    } $tempdir;
}

__END__
