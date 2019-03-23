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

eval { $doit->lwp_mirror };
like $@, qr{ERROR.*url is mandatory};

eval { $doit->lwp_mirror("http://example.com") };
like $@, qr{ERROR.*filename is mandatory};

eval { $doit->lwp_mirror("http://example.com", "/tmp/filename", refresh => 'invalid') };
like $@, qr{ERROR.*refresh may be 'always', 'never' or 'unconditionally'};

eval { $doit->lwp_mirror("http://example.com", "/tmp/filename", refresh => ['digest', '12345678', 'MD5', 'invalid']) };
like $@, qr{ERROR.*\Qrefresh in ARRAY form expects two elements (string 'digest', the digest value and optionally digest type)};

eval { $doit->lwp_mirror("http://example.com", "/tmp/filename", unhandled_option => 1) };
like $@, qr{ERROR.*Unhandled options: unhandled_option};

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

    is $doit->lwp_mirror('file://' . $tmpurl . '/test.txt', "mirrored.txt", debug => 1), 1, 'mirror with default refresh (always)';
    ok File::Compare::compare("test.txt", "mirrored.txt") == 0, 'file was refreshed';

    eval { $doit->lwp_mirror('file://' . $tmpurl . '/does-not-exist', 'mirrored.txt') };
    like $@, qr{ERROR.*mirroring failed: 404 };

    ######################################################################
    # Digest tests
    my $expected_md5 = '5628e5cd7673b0de072df568cebf302e';
    my $expected_sha1 = '2ff34ae1a8bb84346661922448184ac62c567f0c';

    for my $def (
		 [undef,   $expected_md5],
		 ['MD5',   $expected_md5],
		 ['SHA-1', $expected_sha1],
		) {
	my($digest_type, $expected) = @$def;
	my $digest_type_string = defined $digest_type ? $digest_type : "(default=MD5)";
	my @digest_args = ('digest', $expected, (defined $digest_type ? $digest_type : ()));
    SKIP: {
	    if (defined $digest_type && $digest_type eq 'SHA-1') {
		skip "Digest::SHA not available", 3
		    if !module_exists('Digest::SHA');
	    }

	    $doit->unlink("mirrored.txt");

	    is $doit->lwp_mirror('file://' . $tmpurl . '/test.txt', "mirrored.txt", refresh => [@digest_args]), 1, "mirror previously non-existent file with digest $digest_type_string";
	    is $doit->lwp_mirror('file://' . $tmpurl . '/test.txt', "mirrored.txt", refresh => [@digest_args]), 0, "no mirror necessary, with digest $digest_type_string";
    
	    $doit->write_binary("mirrored.txt", <<EOF);
Changed local file.
EOF
	    is $doit->lwp_mirror('file://' . $tmpurl . '/test.txt', "mirrored.txt", refresh => [@digest_args]), 1, "mirror again after changing with digest $digest_type_string";
	}
    }

    ######################################################################
    # unconditionally
    is $doit->lwp_mirror('file://' . $tmpurl . '/test.txt', "unconditionally.txt", refresh => 'unconditionally'), 1, 'refresh unconditionally, first fetch';
    is $doit->lwp_mirror('file://' . $tmpurl . '/test.txt', "unconditionally.txt", refresh => 'unconditionally'), 1, 'refresh unconditionally, second fetch';

} $tmpdir;

__END__
