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
    };
    like $@, qr{^A failure happened}, 'exception was propagated';
    is getcwd, $orig_dir, "directory was restored to $orig_dir, in spite of an exception";
}

SKIP: {
    skip "Cannot remove active directory in MSWin32", 1
	if $^O eq 'MSWin32';
    my $orig_dir = getcwd;
    my $tempdir = tempdir(TMPDIR => 1, CLEANUP => 1);
    in_directory {
	in_directory {
	    my $doit = Doit->init;
	    $doit->rmdir($tempdir);
	} "/";
	is getcwd, "/", 'still in /, temporary directory does not exist anymore';
    } $tempdir;
    is getcwd, $orig_dir, 'everything\'s restored';
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

__END__
