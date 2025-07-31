#!/usr/bin/perl -w
# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2024,2025 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# WWW:  https://github.com/eserte/Doit
#

use strict;
use FindBin;
use lib $FindBin::RealBin;

use File::Temp 'tempdir';
use Hash::Util qw(lock_keys);
use Test::More;

use Doit;

use TestUtil qw(with_unreadable_directory $DOIT %errno_string);

plan skip_all => "symlinks not working or too hard on Windows" if $^O eq 'MSWin32';
plan 'no_plan';

my $tempdir = tempdir('doit_XXXXXXXX', TMPDIR => 1, CLEANUP => 1);
chdir $tempdir or die "Can't chdir to $tempdir: $!";

my $r = Doit->init;
$DOIT = $r;

my $default_ln_nsf_implementation = (
    \&Doit::_ln_nsf == \&Doit::_ln_nsf_system ? "system" :
    \&Doit::_ln_nsf == \&Doit::_ln_nsf_perl   ? "perl" :
    "UNKNOWN!"
);

my @implementations;
push @implementations, ["default ($default_ln_nsf_implementation)", undef];
if ($default_ln_nsf_implementation eq 'system') {
    push @implementations, ["perl",   sub { no warnings 'redefine'; *Doit::_ln_nsf = \&Doit::_ln_nsf_perl }];
} elsif ($default_ln_nsf_implementation eq 'perl') {
    push @implementations, ["system", sub { no warnings 'redefine'; *Doit::_ln_nsf = \&Doit::_ln_nsf_system }];
}

for my $implementation (@implementations) {
    my($implementation_label, $switch_code) = @$implementation;
    diag "Run with implementation $implementation_label";
    $switch_code->() if $switch_code;

    is $r->symlink("tmp/doit-test", "doit-test-symlink"), 1;
    ok -l "doit-test-symlink", 'symlink created';
    is readlink("doit-test-symlink"), "tmp/doit-test", 'symlink points to expected destination';
    is $r->symlink("tmp/doit-test", "doit-test-symlink"), 0;
    ok -l "doit-test-symlink", 'symlink still exists';
    is readlink("doit-test-symlink"), "tmp/doit-test", 'symlink did not change expected destination';
    $r->unlink("doit-test-symlink");
    ok ! -e "doit-test-symlink", 'symlink was removed';

    eval { $r->ln_nsf };
    like $@, qr{oldfile was not specified for ln_nsf};
    eval { $r->ln_nsf("tmp/doit-test") };
    like $@, qr{newfile was not specified for ln_nsf};
    is $r->ln_nsf("tmp/doit-test", "doit-test-symlink2"), 1;
    ok -l "doit-test-symlink2", 'symlink created with ln -nsf';
    is readlink("doit-test-symlink2"), "tmp/doit-test", 'symlink points to expected destination';
    is $r->ln_nsf("tmp/doit-test", "doit-test-symlink2"), 0;
    ok -l "doit-test-symlink2", 'symlink still exists (ln -nsf)';
    is readlink("doit-test-symlink2"), "tmp/doit-test", 'symlink did not change expected destination';
    is $r->ln_nsf("doit-test", "doit-test-symlink2"), 1;
    ok -l "doit-test-symlink2", 'new symlink (ln -nsf)';
    is readlink("doit-test-symlink2"), "doit-test", 'symlink was changed';
    $r->unlink("doit-test-symlink2");
    ok ! -e "doit-test-symlink2", 'symlink was removed';

    $r->mkdir("dir-for-ln-nsf-test");
    ok -d "dir-for-ln-nsf-test";
    eval { $r->ln_nsf("tmp/doit-test", "dir-for-ln-nsf-test") };
    like $@, qr{"dir-for-ln-nsf-test" already exists as a directory};
    ok -d "dir-for-ln-nsf-test", 'directory still exists after failed ln -nsf';

    with_unreadable_directory {
	eval { $r->symlink("target", "unreadable/symlink") };
	like $@, qr{ERROR.*\Q$errno_string{ENOENT}};
	eval { $r->ln_nsf("target", "unreadable/symlink") };
	like $@, qr{(ln -nsf|symlink) target unreadable/symlink failed};
    } "unreadable-dir";

    {
	my @warnings;
	no warnings 'redefine';
	local *Doit::warning = sub { push @warnings, @_ };
	$r->create_file_if_nonexisting("existing-file");
	$r->ln_nsf("doit-test-symlink3", "existing-file");
	like "@warnings", qr{already exists, but is not a symlink --- possibly oldfile and newfile arguments are swapped}, 'warning about swapped arguments';
	ok -l "existing-file", 'problematic operation was done';
	$r->unlink("existing-file");
    }
}

chdir '/'; # for File::Temp
