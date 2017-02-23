# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2017 Slaven Rezic. All rights reserved.
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
# WWW:  http://www.rezic.de/eserte/
#

package Doit::Deb; # Convention: all commands here should be prefixed with 'deb_'

use strict;
use vars qw($VERSION);
$VERSION = '0.01';

sub new { bless {}, shift }
sub functions { qw(deb_install_packages deb_missing_packages) }

sub deb_install_packages {
    my($self, @packages) = @_;
    my @missing_packages = $self->deb_missing_packages(@packages); # XXX cmd vs. info???
    if (@missing_packages) {
	$self->system('apt-get', '-y', 'install', @missing_packages);
    }
    @missing_packages;
}


sub deb_missing_packages {
    my($self, @packages) = @_;

    my @missing_packages;

    if (@packages) {
	require IPC::Open3;
	require Symbol;

	my %seen_packages;
	my %required_version;
	for my $package (@packages) {
	    if (ref $package eq 'ARRAY') {
		my($package_name, $package_version) = @$package;
		$required_version{$package_name} = $package_version;
		$package = $package_name;
	    }
	}
	my @cmd = ('dpkg-query', '-W', '-f=${Package}\t${Status}\t${Version}\n', @packages);
	my $err = Symbol::gensym();
	my $fh;
	# XXX how to run on remote? should $self->run be optionally used?
	my $pid = IPC::Open3::open3(undef, $fh, $err, @cmd)
	    or die "Error running '@cmd': $!";
	while(<$fh>) {
	    chomp;
	    if (m{^([^\t]+)\t([^\t]+)\t([^\t]*)$}) {
		if ($2 ne 'install ok installed') {
		    push @missing_packages, $1;
		}
		if ($required_version{$1} && $required_version{$1} ne $3) {
		    push @missing_packages, $1;
		}
		$seen_packages{$1} = 1;
	    } else {
		warn "ERROR: cannot parse $_, ignore line...\n";
	    }
	}
	waitpid $pid, 0;
	for my $package (@packages) {
	    if (!$seen_packages{$package}) {
		push @missing_packages, $package;
	    }
	}
    }
    @missing_packages;
}

1;

__END__
