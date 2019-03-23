#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use FindBin;

use File::Glob qw(bsd_glob);
use Test::More;

use Doit;
use Doit::Extcmd 'is_in_path';

my $man3path = "$FindBin::RealBin/../blib/man3";
my $has_blib_man3 = -d $man3path;
plan skip_all => "manifypods probably not called" if !$has_blib_man3;
plan 'no_plan';

my $doit = Doit->init;

ok -s bsd_glob("$man3path/Doit.3*"),     'non-empty manpage for Doit'
    or diag($doit->info_qx(qw(ls -al), $man3path));
ok -s bsd_glob("$man3path/Doit*Deb.3*"), 'non-empty manpage for Doit::Deb'
    or diag($doit->info_qx(qw(ls -al), $man3path));

my $file_prg = is_in_path('file');
SKIP: {
    skip "file command not installed", 1 if !$file_prg;
    like get_filetype(bsd_glob("$man3path/Doit.3*")),     qr{troff}, 'Doit manpage looks like a manpage';
    like get_filetype(bsd_glob("$man3path/Doit*Deb.3*")), qr{troff}, 'Doit::Deb manpage looks like a manpage';
}

sub get_filetype {
    my($file) = @_;
    chomp(my($filetype) = $doit->info_qx({quiet => 1}, $file_prg, $file));
    $filetype;
}

__END__
