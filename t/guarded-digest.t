#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use FindBin;
use lib "$FindBin::RealBin";

use File::Temp 'tempdir';
use Test::More 'no_plan';
use Doit;
use Doit::File 'digest_matches';

use TestUtil qw(module_exists);

my $d = Doit->init;
$d->add_component('guarded');

my $tmpdir = tempdir(CLEANUP => 1, TMPDIR => 1);

{
    my $file = "$tmpdir/file";

    $d->guarded_step
	(
	 'create digested file (previously non-existent)',
	 ensure => sub {
	     digest_matches($file, "ff22941336956098ae9a564289d1bf1b");
	 },
	 using => sub {
	     open my $fh, ">", $file;
	     binmode $fh;
	     print $fh "This is a test\n";
	 },
	);
    ok -e $file, "guarded_step passed and file exists";

    $d->guarded_step
	(
	 'digested file already exists',
	 ensure => sub {
	     digest_matches($file, "ff22941336956098ae9a564289d1bf1b");
	 },
	 using => sub {
	     die "This should never run!";
	 },
	);
    pass "using step was really skipped";

 SKIP: {
	skip "Digest::SHA1 not available (not a core perl module)", 1
	    if !module_exists('Digest::SHA1');

	$d->guarded_step
	    ('use sha1',
	     ensure => sub {
		 digest_matches($file, "3c1bb0cd5d67dddc02fae50bf56d3a3a4cbc7204", "SHA1");
	     },
	     using => sub {
		 die "This should never run!";
	     },
	    );
	pass "using step (with SHA1 digest) was really skipped";
    }

    $d->unlink($file);
    $d->touch($file);
    $d->guarded_step
	(
	 'create digested file (previously empty)',
	 ensure => sub {
	     digest_matches($file, "ff22941336956098ae9a564289d1bf1b");
	 },
	 using => sub {
	     open my $fh, ">", $file;
	     binmode $fh;
	     print $fh "This is a test\n";
	 },
	);
    ok -e $file, "guarded_step passed and file exists";

    eval {
	$d->guarded_step
	    (
	     'ensure never satisfied',
	     ensure => sub {
		 digest_matches($file, "wrong digest");
	     },
	     using => sub {
		 open my $fh, ">", $file;
		 binmode $fh;
		 print $fh "This is a test\n";
	     },
	    );
    };
    like $@, qr{ERROR.*still fails};
}
