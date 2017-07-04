#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use Test::More 'no_plan';
use Doit;
use File::Temp 'tempdir';

sub slurp ($) { open my $fh, shift or die $!; local $/; <$fh> }

my $tempdir = tempdir(CLEANUP => 1);

my $d = Doit->init;

$d->write_binary("$tempdir/srcfile", "source data\n");
$d->mkdir("$tempdir/destdir1");
$d->mkdir("$tempdir/destdir2");

# copy with fully qualified path
$d->copy("$tempdir/srcfile", "$tempdir/destdir1/destfile");
ok -e "$tempdir/destdir1/destfile";
is slurp("$tempdir/destdir1/destfile"), "source data\n";

$d->copy("$tempdir/srcfile", "$tempdir/destdir1/destfile"); # no-op

# copy with destination directory only
$d->copy("$tempdir/srcfile", "$tempdir/destdir2");
ok -e "$tempdir/destdir2/srcfile";
is slurp("$tempdir/destdir2/srcfile"), "source data\n";

# copy to non-existent directory
eval { $d->copy("$tempdir/srcfile", "$tempdir/non-existent-directory/destfile") };
like $@, qr{Copy failed: No such file or directory};

# copy non-existent source file
eval { $d->copy("$tempdir/non-existent-srcfile", "$tempdir/destdir2") };
like $@, qr{Copy failed: No such file or directory};

__END__
