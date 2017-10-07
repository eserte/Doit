#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use Cwd 'getcwd';
use Doit;
use Doit::Util;
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

__END__
