#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use Doit;
use Doit::Extcmd;
use File::Glob 'bsd_glob';
use File::Temp 'tempdir';
use Test::More;

sub slurp ($) { open my $fh, shift or die $!; local $/; <$fh> }
sub slurp_utf8 ($) { open my $fh, shift or die $!; binmode $fh, ':encoding(utf-8)'; local $/; <$fh> }

return 1 if caller;

require FindBin;
{ no warnings 'once'; push @INC, $FindBin::RealBin; }
require TestUtil;

sub no_leftover_tmp ($;$) {
    my($dir, $suffix) = @_;
    $suffix = '.tmp' if !defined $suffix;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my @files = bsd_glob("$dir/*$suffix");
    is_deeply \@files, [], "no temporary file left-overs with suffix $suffix in $dir";
}

plan 'no_plan';

my $doit = Doit->init;
$doit->add_component('file');

my $doit_dryrun = do {
    local @ARGV = '--dry-run';
    Doit->init;
};
ok $doit_dryrun->is_dry_run, 'created dry-run Doit object';
# Accidentally it's not required to call add_component('file') here,
# as the add_component calls affect the class, not the object.

my $tempdir = tempdir('doit_XXXXXXXX', TMPDIR => 1, CLEANUP => 1);
$doit->mkdir("$tempdir/another_tmp");

{
    eval { $doit->file_atomic_write };
    like $@, qr{file parameter is missing}i, "too few params";
}

{
    eval { $doit->file_atomic_write("$tempdir/1st") };
    like $@, qr{code parameter is missing}i, "too few params";
    ok !-e "$tempdir/1st", "file was not created";
}

{
    eval { $doit->file_atomic_write("$tempdir/1st", "not a sub") };
    like $@, qr{code parameter should be an anonymous subroutine or subroutine reference}i, "wrong type";
    ok !-e "$tempdir/1st", "file was not created";
}

{
    eval { $doit->file_atomic_write("$tempdir/1st", sub { }, does_not_exist => 1) };
    like $@, qr{unhandled option}i, "unhandled option error";
    ok !-e "$tempdir/1st", "file was not created";
}

{
    eval { $doit->file_atomic_write("$tempdir/1st", sub { die "something failed" }) };
    like $@, qr{something failed}i, "exception in code";
    ok !-e "$tempdir/1st", "file was not created";
    no_leftover_tmp $tempdir;
}

{
    $doit->file_atomic_write("$tempdir/1st", sub {
				 my $fh = shift;
				 binmode $fh, ':encoding(utf-8)';
				 print $fh "\x{20ac}uro\n";
			     });

    ok -s "$tempdir/1st", 'Created file exists and is non-empty';
    is slurp_utf8("$tempdir/1st"), "\x{20ac}uro\n", 'expected content';
    no_leftover_tmp $tempdir;
}

{
    $doit->chmod(0600, "$tempdir/1st");
    my $mode_before = (stat("$tempdir/1st"))[2];

    $doit->file_atomic_write("$tempdir/1st", sub {
				 my $fh = shift;
				 print $fh "changed content\n";
			     });
    is slurp("$tempdir/1st"), "changed content\n", 'content of existent file changed';
    my $mode_after = (stat("$tempdir/1st"))[2];
    is $mode_after, $mode_before, 'mode was preserved';
    no_leftover_tmp $tempdir;
}

{
    $doit->file_atomic_write("$tempdir/1st", sub {
				 my($fh, $filename) = @_;
				 $doit->system($^X, '-e', 'open my $ofh, ">", shift or die $!; print $ofh "external program writing the contents\n"; close $ofh or die $!', $filename);
			     });
    is slurp("$tempdir/1st"), "external program writing the contents\n", 'filename parameter was used';
    no_leftover_tmp $tempdir;
}

for my $opt_def (
		 [suffix => '.another_suffix'],
		 [dir => "$tempdir/another_tmp"],
		) {
    my $opt_spec = "@$opt_def";
    $doit->file_atomic_write("$tempdir/1st",
			     sub {
				 my $fh = shift;
				 print $fh $opt_spec;
			     }, @$opt_def);
    is slurp("$tempdir/1st"), $opt_spec, "atomic write with opts: $opt_spec";
    if ($opt_def->[0] eq 'suffix') {
	no_leftover_tmp $tempdir, $opt_def->[1];
    } else {
	no_leftover_tmp $tempdir;
    }
}

{ # dry-run check
    my $old_content = slurp("$tempdir/1st");
    $doit_dryrun->file_atomic_write("$tempdir/1st", sub {
					my $fh = shift;
					print $fh "this is dry run mode\n";
				    });
    is slurp("$tempdir/1st"), $old_content, 'nothing changed in dry run mode';
    no_leftover_tmp $tempdir;
}

SKIP: {
    skip "No BSD::Resource available", 1
	if !eval { require BSD::Resource; 1 };
    skip "No fork on Windows", 1
	if $^O eq 'MSWin32';
    my $pid = fork;
    die "Cannot fork: $!" if !defined $pid;
    if ($pid == 0) {
	my $limit_fsize = 100;
	my $write_size = 1024;
	require BSD::Resource;
	BSD::Resource::setrlimit(BSD::Resource::RLIMIT_FSIZE(), $limit_fsize, $limit_fsize)
	    or die "Cannot limit fsize: $!";
	$SIG{XFSZ} = 'IGNORE'; # otherwise the process would be just killed
	eval {
	    $doit->file_atomic_write("$tempdir/1st",
				     sub {
					 my $fh = shift;
					 print $fh "x" x $write_size;
				     }); # should fail
	};
	if ($@ =~ m{Error while closing temporary file}) {
	    #diag "Got $@";
	    exit 0;
	} else {
	    diag "No or unexpected exception: $@";
	    exit 1;
	}
    }
    waitpid $pid, 0;
    is $?, 0, 'Write failed, probably got EFBIG';
    no_leftover_tmp $tempdir;
}

SKIP: {
    skip "No /dev/full available", 1 if !-w '/dev/full';
    my $old_content = slurp("$tempdir/1st");
    eval { 
	$doit->file_atomic_write("$tempdir/1st",
				 sub {
				     my $fh = shift;
				     print $fh "/dev/full testing\n";
				 }, dir => '/dev/full');
    };
    like $@, qr{Error while closing temporary file}, 'Cannot write to /dev/full as expected';
    is slurp("$tempdir/1st"), $old_content, 'content still unchanged';
    no_leftover_tmp $tempdir;
}

SKIP: {
    skip "Hangs on travis-ci", 1 if $ENV{TRAVIS}; # reason unknown
    skip "Mounting fs only implemented for linux", 1 if $^O ne 'linux';
    skip "Cannot mount in linux containers", 1 if TestUtil::in_linux_container($doit);
    skip "dd not available", 1 if !Doit::Extcmd::is_in_path("dd");
    skip "mkfs not available", 1 if !-x "/sbin/mkfs";
    my $sudo = TestUtil::get_sudo($doit, info => \my %info);
    skip $info{error}, 1 if !$sudo;

    my $fs_file = "$tempdir/testfs";
    $doit->system(qw(dd if=/dev/zero), "of=$fs_file", qw(count=1 bs=1MB));
    $doit->system(qw(/sbin/mkfs -t ext3), $fs_file);
    my $mnt_point = "$tempdir/testmnt";
    $doit->mkdir($mnt_point);
    $sudo->system(qw(mount -o loop), $fs_file, $mnt_point);
    $sudo->mkdir("$mnt_point/dir");
    $sudo->chown($<, undef, "$mnt_point/dir");

    $doit->utime(0,0,"$tempdir/1st");
    my $mode_before = (stat("$tempdir/1st"))[2];
    my $time = time;
    $doit->file_atomic_write("$tempdir/1st",
			     sub {
				 my $fh = shift;
				 print $fh "File::Copy::move testing\n";
			     }, dir => "$mnt_point/dir");
    is slurp("$tempdir/1st"), "File::Copy::move testing\n", "content OK after using cross-mount move";
    my $mode_after = (stat("$tempdir/1st"))[2];
    is $mode_after, $mode_before, 'mode was preserved';
    my $mtime_after = (stat("$tempdir/1st"))[9];
    cmp_ok $mtime_after, ">=", $time, 'current mtime';

    $doit->file_atomic_write("$tempdir/fresh",
			     sub {
				 my $fh = shift;
				 print $fh "fresh file with File::Copy::move\n";
			     }, dir => "$mnt_point/dir");
    is slurp("$tempdir/fresh"), "fresh file with File::Copy::move\n", "cross-mount move with fresh file";

    { # dry-run check
	my $old_content = slurp("$tempdir/1st");
	$doit_dryrun->file_atomic_write("$tempdir/1st", sub {
					    my $fh = shift;
					    print $fh "this is dry run mode\n";
					}, dir => "$mnt_point/dir");
	is slurp("$tempdir/1st"), $old_content, 'nothing changed in dry run mode';
	no_leftover_tmp "$mnt_point/dir", '';
    }

    $sudo->system(qw(umount), $mnt_point);
}
