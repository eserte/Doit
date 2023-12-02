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

use TestUtil qw(module_exists);

my $d = Doit->init;
$d->add_component('guarded');
$d->add_component('file');

my $tmpdir = tempdir(CLEANUP => 1, TMPDIR => 1);

{
    my $file = "$tmpdir/file";

    $d->guarded_step
	(
	 'create digested file (previously non-existent)',
	 ensure => sub {
	     $d->file_digest_matches($file, "ff22941336956098ae9a564289d1bf1b");
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
	     $d->file_digest_matches($file, "ff22941336956098ae9a564289d1bf1b");
	 },
	 using => sub {
	     die "This should never run!";
	 },
	);
    pass "using step was really skipped";

 SKIP: {
	skip "Digest::SHA not available", 1
	    if !module_exists('Digest::SHA');

	for my $def (
	    ['SHA-1',   '3c1bb0cd5d67dddc02fae50bf56d3a3a4cbc7204'],
	    ['SHA-256', '9d63c3b5b7623d1fa3dc7fd1547313b9546c6d0fbbb6773a420613b7a17995c8'],
	    ['SHA-512', '62f1c73922ba448579d9229f932e747c23d53400a6fb826c6ea5f478247420c62b681cd636840e0ae8556bcde856a24c0123c501aa3967c42530e3be8cb6de75'],
	) {
	    my($digest_algorithm, $expected_digest) = @$def;
	    $d->guarded_step
		("use $digest_algorithm (through Digest::SHA)",
		 ensure => sub {
		     $d->file_digest_matches($file, $expected_digest, $digest_algorithm);
		 },
		 using => sub {
		     die "This should never run!";
		 },
		);
	    pass "using step (with $digest_algorithm digest) was really skipped";
	}
    }

 SKIP: {
	skip "Digest::SHA1 not available (not a core perl module)", 1
	    if !module_exists('Digest::SHA1');

	$d->guarded_step
	    ('use sha1',
	     ensure => sub {
		 $d->file_digest_matches($file, "3c1bb0cd5d67dddc02fae50bf56d3a3a4cbc7204", "SHA1");
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
	     $d->file_digest_matches($file, "ff22941336956098ae9a564289d1bf1b");
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
		 $d->file_digest_matches($file, "wrong digest");
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
