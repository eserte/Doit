#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use FindBin;
use lib $FindBin::RealBin;

use File::Compare ();
use File::Temp qw(tempdir);
use Test::More;

use Doit;
use Doit::Util qw(in_directory);

use TestUtil qw(module_exists);

if (!module_exists('LWP::UserAgent')) {
    plan skip_all => 'LWP::UserAgent not installed';
}

plan 'no_plan';

my $doit = Doit->init;
$doit->add_component('lwp');

my $tmpdir = tempdir("doit-lwp-XXXXXXXX", CLEANUP => 1, TMPDIR => 1);

in_directory {
    $doit->write_binary("test.txt", <<EOF);
Sample text file.
EOF

    my $tmpurl = $tmpdir;
    if ($^O eq 'MSWin32') {
	$tmpurl =~ s{\\}{/}g;
    }

    is $doit->lwp_mirror('file://' . $tmpurl . '/test.txt', "mirrored.txt"), 1, 'mirror was done';
    is $doit->lwp_mirror('file://' . $tmpurl . '/test.txt', "mirrored.txt"), 0, 'no change';
    ok File::Compare::compare("test.txt", "mirrored.txt") == 0, 'mirrored file has same contents'
	or diag eval { $doit->info_qx({quiet=>1}, 'diff', '-u', 'test.txt', 'mirrored.txt') };

    $doit->write_binary("test.txt", <<EOF);
Changed sample text file.
EOF
    $doit->utime(1234,1234,"mirrored.txt"); # simulate outdated file

    is $doit->lwp_mirror('file://' . $tmpurl . '/test.txt', "mirrored.txt", refresh => 'never'), 0, 'no mirror with refresh => never';
    ok File::Compare::compare("test.txt", "mirrored.txt") != 0, 'file was not changed';

    is $doit->lwp_mirror('file://' . $tmpurl . '/test.txt', "mirrored.txt", debug => 0), 1, 'mirror with default refresh (always)';
    ok File::Compare::compare("test.txt", "mirrored.txt") == 0, 'file was refreshed';

} $tmpdir;

__END__
