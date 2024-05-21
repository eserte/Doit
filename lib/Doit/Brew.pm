# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2017,2018,2022,2024 Slaven Rezic. All rights reserved.
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
# WWW:  http://www.rezic.de/eserte/
#

package Doit::Brew; # Convention: all commands here should be prefixed with 'brew_'

use strict;
use warnings;
our $VERSION = '0.013';

use Doit::Log;

sub new { bless {}, shift }
sub functions { qw(brew_install_packages brew_missing_packages can_brew brew_get_cellar) }

sub can_brew {
    my($self) = @_;
    $self->which('brew') ? 1 : 0;
}

sub brew_install_packages {
    my($self, @packages) = @_;
    my @missing_packages = $self->brew_missing_packages(@packages);
    if (@missing_packages) {
	$self->system('brew', 'install', @missing_packages);
    }
    @missing_packages;
}

{
    my $cached_cellar;

    sub brew_missing_packages {
	my($self, @packages) = @_;

	$cached_cellar ||= $self->brew_get_cellar;

	my @missing_packages;
	for my $package (@packages) {
	    if (!defined $cached_cellar || !-d "$cached_cellar/$package") {
		push @missing_packages, $package;
	    }
	}
	@missing_packages;
    }
}

sub brew_get_cellar {
    my($self) = @_;
    return $ENV{HOMEBREW_CELLAR}          if defined $ENV{HOMEBREW_CELLAR} && -d $ENV{HOMEBREW_CELLAR};
    return "$ENV{HOMEBREW_PREFIX}/Cellar" if defined $ENV{HOMEBREW_PREFIX} && -d "$ENV{HOMEBREW_PREFIX}/Cellar";
    return "/usr/local/Cellar"            if -d "/usr/local/Cellar";
    return "/opt/homebrew/Cellar"         if -d "/opt/homebrew/Cellar";

    for my $line (split /\n/, eval { $self->info_qx({quiet=>1}, 'brew', 'config') }) {
	if ($line =~ /^\s*HOMEBREW_PREFIX:\s*(.*)/) {
	    my $cellar = "$1/Cellar";
	    return $cellar if -d $cellar;
	    last;
	}
    }

    warning "Can't find homebrew cellar, expect homebrew-related things to fail.";
    return undef;
}

1;

__END__
