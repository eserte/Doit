#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use File::Temp qw(tempdir);
use Test::More;

BEGIN {
    plan skip_all => 'No Capture::Tiny available' if !eval { require Capture::Tiny; Capture::Tiny->import('capture'); 1 };
    plan skip_all => 'No Term::ANSIColor available' if !eval { require Term::ANSIColor; Term::ANSIColor->import('colorstrip'); 1 };
}
plan 'no_plan';

use Doit;
use Doit::Extcmd qw(is_in_path);

sub slurp ($) { open my $fh, shift or die $!; local $/; <$fh> }

my $doit = Doit->init;

my $dir = tempdir(CLEANUP => 1);

chdir $dir or die $!;

{
    eval {
	$doit->copy;
    };
    like colorstrip($@), qr{^ERROR: Expecting two arguments: from and to filenames }, 'not enough arguments';
}

{
    eval {
	$doit->copy({unhandled_option=>1}, "unused", "unused");
    };
    like colorstrip($@), qr{^ERROR: Unhandled options: unhandled_option }, 'unhandled option';
}

$doit->write_binary({quiet => 2}, "test-file", "content");

{
    my($stdout, $stderr) = capture {
	$doit->copy("test-file", "test-file-copied");
    };
    is $stdout, '';
    like colorstrip($stderr), qr{^\QINFO: copy test-file test-file-copied (destination does not exist)\E$}, 'copy to non-existing file';
    is slurp("test-file-copied"), "content";
}

{
    my($stdout, $stderr) = capture {
	$doit->copy("test-file", "test-file-copied");
    };
    is $stdout, '';
    is $stderr, '', 'copy to same file: no-op';
    is slurp("test-file-copied"), "content";
}

$doit->write_binary({quiet => 2}, "test-file", "changed content");

{
    my($stdout, $stderr) = capture {
	$doit->copy("test-file", "test-file-copied");
    };
    is $stdout, '';
    like colorstrip($stderr), qr{^\QINFO: copy test-file test-file-copied}, 'changed contents';
    if (is_in_path 'diff') {
	like $stderr, qr{^\Q--- test-file-copied}sm, 'looks like a diff header';
	like $stderr, qr{^\Q+++ test-file}sm, 'looks like a diff header';
	like $stderr, qr{^\Q-content}sm, 'looks like diff body';
	like $stderr, qr{^\Q+changed content}sm, 'looks like diff body';
    }
    is slurp("test-file-copied"), "changed content";
}

$doit->write_binary({quiet => 2}, "test-file", "again changed content");

{
    my($stdout, $stderr) = capture {
	$doit->copy({quiet => 1}, "test-file", "test-file-copied");
    };
    is $stdout, '';
    is colorstrip($stderr), qq{INFO: copy test-file test-file-copied\n}, 'changed contents, without diff';
    is slurp("test-file-copied"), "again changed content";
}

{
    my($stdout, $stderr) = capture {
	$doit->copy({quiet => 1}, "test-file", "new-test-file-copied");
    };
    is $stdout, '';
    is colorstrip($stderr), qq{INFO: copy test-file new-test-file-copied (destination does not exist)\n};
    is slurp("test-file-copied"), "again changed content";
}

chdir "/";
