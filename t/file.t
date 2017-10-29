#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use Doit;
use File::Temp 'tempdir';
use Test::More;

sub slurp ($) { open my $fh, shift or die $!; local $/; <$fh> }
sub slurp_utf8 ($) { open my $fh, shift or die $!; binmode $fh, ':encoding(utf-8)'; local $/; <$fh> }

return 1 if caller;

plan 'no_plan';

my $doit = Doit->init;
$doit->add_component('file');

my $tempdir = tempdir('doit_XXXXXXXX', TMPDIR => 1, CLEANUP => 1);
$doit->mkdir("$tempdir/another_tmp");

{
    eval { $doit->file_atomic_write_fh };
    like $@, qr{file parameter is missing}i, "too few params";
}

{
    eval { $doit->file_atomic_write_fh("$tempdir/1st") };
    like $@, qr{code parameter is missing}i, "too few params";
    ok !-e "$tempdir/1st", "file was not created";
}

{
    eval { $doit->file_atomic_write_fh("$tempdir/1st", "not a sub") };
    like $@, qr{code parameter should be an anonymous subroutine or subroutine reference}i, "wrong type";
    ok !-e "$tempdir/1st", "file was not created";
}

{
    eval { $doit->file_atomic_write_fh("$tempdir/1st", sub { }, does_not_exist => 1) };
    like $@, qr{unhandled option}i, "unhandled option error";
    ok !-e "$tempdir/1st", "file was not created";
}

{
    eval { $doit->file_atomic_write_fh("$tempdir/1st", sub { die "something failed" }) };
    like $@, qr{something failed}i, "exception in code";
    ok !-e "$tempdir/1st", "file was not created";
}

{
    $doit->file_atomic_write_fh("$tempdir/1st", sub {
				    my $fh = shift;
				    binmode $fh, ':encoding(utf-8)';
				    print $fh "\x{20ac}uro\n";
				});

    ok -s "$tempdir/1st", 'Created file exists and is non-empty';
    is slurp_utf8("$tempdir/1st"), "\x{20ac}uro\n", 'expected content';
}

{
    $doit->chmod(0600, "$tempdir/1st");
    my $mode_before = (stat("$tempdir/1st"))[2];

    $doit->file_atomic_write_fh("$tempdir/1st", sub {
				    my $fh = shift;
				    print $fh "changed content\n";
				});
    is slurp("$tempdir/1st"), "changed content\n", 'content of existent file changed';
    my $mode_after = (stat("$tempdir/1st"))[2];
    is $mode_after, $mode_before, 'mode was preserved';
}

for my $opt_def (
		 [suffix => '.another_suffix'],
		 [dir => "$tempdir/another_tmp"],
		) {
    my $opt_spec = "@$opt_def";
    $doit->file_atomic_write_fh("$tempdir/1st",
				sub {
				    my $fh = shift;
				    print $fh $opt_spec;
				}, @$opt_def);
    is slurp("$tempdir/1st"), $opt_spec, "atomic write with opts: $opt_spec";
}
