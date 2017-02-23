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
use lib ("$FindBin::RealBin/../lib");

use Test::More 'no_plan';

use Doit;

my $d = Doit->init;
$d->add_component('deb');

{
    my @missing_packages = $d->deb_missing_packages('this-does-not-exist');
    is_deeply \@missing_packages, ['this-does-not-exist'];
}

{
    my @missing_packages = $d->deb_missing_packages('perl');
    is_deeply \@missing_packages, [];
}

{
    my @installed_packages = $d->deb_install_packages('perl');
    is_deeply \@installed_packages, [];
}

__END__
