#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use File::Compare ();
use File::Temp qw(tempdir);
use Test::More;

use Doit;
use Doit::Util qw(in_directory);

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

# REPO BEGIN
# REPO NAME module_exists /home/slaven.rezic/src/srezic-repository 
# REPO MD5 1ea9ee163b35d379d89136c18389b022

#=head2 module_exists($module)
#
#Return true if the module exists in @INC or if it is already loaded.
#
#=cut

sub module_exists {
    my($filename) = @_;
    $filename =~ s{::}{/}g;
    $filename .= ".pm";
    return 1 if $INC{$filename};
    foreach my $prefix (@INC) {
	my $realfilename = "$prefix/$filename";
	if (-r $realfilename) {
	    return 1;
	}
    }
    return 0;
}
# REPO END

__END__
