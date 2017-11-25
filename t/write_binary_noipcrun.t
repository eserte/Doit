#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use FindBin;

if (!eval { require Devel::Hide; 1 }) {
    require Test::More;
    Test::More::plan(skip_all => "No Devel::Hide available");
}

$ENV{DEVEL_HIDE_PM} = 'IPC::Run';
system $^X, "-MDevel::Hide", "$FindBin::RealBin/write_binary.t";

__END__
