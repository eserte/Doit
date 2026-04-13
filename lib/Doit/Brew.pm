# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2017,2018,2022,2024,2025,2026 Slaven Rezic. All rights reserved.
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# WWW:  https://github.com/eserte/Doit
#

package Doit::Brew; # Convention: all commands here should be prefixed with 'brew_'

use strict;
use warnings;
our $VERSION = '0.015';

use Doit::Log;

sub new { bless {}, shift }
sub functions { qw(brew_install_packages brew_missing_packages can_brew brew_get_cellar brew_without) }

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
	    my $formula_name = $package =~ m{.*/(.+)$} ? $1 : $package;
	    if (!defined $cached_cellar || !-d "$cached_cellar/$formula_name") {
		push @missing_packages, $package;
	    }
	}
	@missing_packages;
    }
}

sub brew_get_cellar {
    my($self) = @_;

    # First try environment variables (fastest, no external command called)
    return $ENV{HOMEBREW_CELLAR}          if defined $ENV{HOMEBREW_CELLAR} && -d $ENV{HOMEBREW_CELLAR};
    return "$ENV{HOMEBREW_PREFIX}/Cellar" if defined $ENV{HOMEBREW_PREFIX} && -d "$ENV{HOMEBREW_PREFIX}/Cellar";

    # Heuristics depending on architcture
    chomp(my $arch = eval { $self->info_qx({quiet => 1}, qw(uname -m)) });
    my @cellar_candidates = ($arch eq 'arm64' ? ('/opt/homebrew/Cellar', '/usr/local/Cellar') : ('/usr/local/Cellar', '/opt/homebrew/Cellar'));
    for my $cellar_candidate (@cellar_candidates) {
	return $cellar_candidate  if -d $cellar_candidate;
    }

    # use brew config (maybe slow?)
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

sub brew_without {
    my($self, $code) = @_;

    my @brew_prefixes = grep { defined && length }
        $ENV{HOMEBREW_PREFIX},
        '/home/linuxbrew/.linuxbrew',  # Linux
        '/opt/homebrew',               # macOS Apple Silicon
	## not activated --- /usr/local may be used for non-brew stuff
        # '/usr/local',                  # macOS Intel
	;
    @brew_prefixes = do { my %seen; grep { !$seen{$_}++ } @brew_prefixes }; # dedup

    my $new_path = join ':',
        grep {
            my $p = $_;
            !grep { $p =~ m{^\Q$_\E(?:/|$)} } @brew_prefixes
        }
        split /:/, ($ENV{PATH} || '');

    local %ENV = %ENV;
    $self->setenv(PATH => $new_path);
    $self->unsetenv($_) for qw(
        HOMEBREW_PREFIX
        HOMEBREW_CELLAR
        HOMEBREW_REPOSITORY
    );

    $code->();
}

1;

__END__
