#!/usr/bin/perl -w
# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2017 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
# WWW:  http://www.rezic.de/eserte/
#

use strict;
use FindBin;
use lib "$FindBin::RealBin/lib";
use File::Basename;
use Doit;

my $doit = Doit->init;

if (basename($0) eq 'Build.PL') {
    $doit->symlink('Build.PL', 'Build');
    exit;
}

my $action = shift || 'build';
{
    no strict 'refs';
    &$action;
}

sub build {
    die "NYI";
}

sub test {
    $doit->system('prove', '-l', 't'); # use right perl?
}

sub cover {
    $doit->system('prove', '--exec', "$^X -Ilib -MDevel::Cover", 't');
    $doit->system('cover');
}

sub show_cover {
    cover();
    $doit->system('firefox', "$FindBin::RealBin/cover_db/coverage.html");
}

__END__
