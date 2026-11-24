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
our $VERSION = '0.017';

use Doit::Log;

sub new { bless {}, shift }
sub functions { qw(brew_install_packages brew_missing_packages can_brew brew_get_directory brew_get_cellar brew_get_caskroom brew_without brew_with) }

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
    my $cached_caskroom;

    sub brew_missing_packages {
	my($self, @packages) = @_;

	$cached_cellar   ||= $self->brew_get_cellar;
	$cached_caskroom ||= $self->brew_get_caskroom;

	my @missing_packages;
	for my $package (@packages) {
	    my $formula_name = $package =~ m{.*/(.+)$} ? $1 : $package;
	    if (!((defined $cached_cellar && -d "$cached_cellar/$formula_name") ||
		  (defined $cached_caskroom && -d "$cached_caskroom/$formula_name"))) {
		push @missing_packages, $package;
	    }
	}
	@missing_packages;
    }
}

sub brew_get_directory {
    my($self, $directory) = @_;

    # First try environment variables (fastest, no external command called)
    my $env_var = "HOMEBREW_" . uc($directory);
    return $ENV{$env_var}                     if defined $ENV{$env_var} && -d $ENV{$env_var};
    return "$ENV{HOMEBREW_PREFIX}/$directory" if defined $ENV{HOMEBREW_PREFIX} && -d "$ENV{HOMEBREW_PREFIX}/$directory";

    # Heuristics depending on architcture and OS
    chomp(my $arch = eval { $self->info_qx({quiet => 1}, qw(uname -m)) });
    my @subdir_candidates;
    if ($^O eq 'linux') {
        @subdir_candidates = "/home/linuxbrew/.linuxbrew/$directory";
    } else {
	@subdir_candidates = ($arch eq 'arm64' ? ("/opt/homebrew/$directory", "/usr/local/$directory") : ("/usr/local/$directory", "/opt/homebrew/$directory"));
    }
    for my $subdir_candidate (@subdir_candidates) {
	return $subdir_candidate  if -d $subdir_candidate;
    }

    # use brew config (maybe slow?)
    for my $line (split /\n/, eval { $self->info_qx({quiet=>1}, 'brew', 'config') }) {
	if ($line =~ /^\s*HOMEBREW_PREFIX:\s*(.*)/) {
	    my $fullpath = "$1/$directory";
	    return $fullpath if -d $fullpath;
	    last;
	}
    }

    warning "Can't find homebrew $directory, expect homebrew-related things to fail.";
    return undef;
}

sub brew_get_cellar {
    my($self) = @_;
    $self->brew_get_directory('Cellar');
}

sub brew_get_caskroom {
    my($self) = @_;
    $self->brew_get_directory('Caskroom');
}

sub brew_with {
    my($self, @args) = @_;

    my %options; if (@args && ref $args[0] eq 'HASH') { %options = %{ shift @args } }
    my $quiet = delete $options{quiet};
    error "Unhandled options: " . join(" ", %options) if %options;

    my $code = shift @args;

    error "Too many arguments to brew_with() call" if @args;

    my @brew_prefix_candidates = (
        '/home/linuxbrew/.linuxbrew',  # Linux
        '/opt/homebrew',               # macOS Apple Silicon
        '/usr/local',                  # macOS Intel
    );

    my $brew_prefix;
    for my $candidate (@brew_prefix_candidates) {
	if (-x "$candidate/bin/brew") {
	    $brew_prefix = $candidate;
	    last;
	}
    }

    if (!defined $brew_prefix) {
	error "Cannot find a homebrew installation";
    }

    my $brew_bin = "$brew_prefix/bin";

    my $new_path = join ':', $brew_bin, grep { $_ ne $brew_bin } split(/:/, ($ENV{PATH} || ''));

    local %ENV = %ENV;

    {
	local *Doit::Log::info = $quiet ? sub {} : \&Doit::Log::info;
	$self->setenv(PATH => $new_path);
	$self->setenv(HOMEBREW_PREFIX    => $brew_prefix);
	$self->setenv(HOMEBREW_CELLAR    => "$brew_prefix/Cellar")    if -d "$brew_prefix/Cellar";
	$self->setenv(HOMEBREW_REPOSITORY => $brew_prefix)            if -d "$brew_prefix/.git" || -d "$brew_prefix/Library";
    }

    $code->();
}

sub brew_without {
    my($self, @args) = @_;

    my %options; if (@args && ref $args[0] eq 'HASH') { %options = %{ shift @args } }
    my $quiet = delete $options{quiet};
    error "Unhandled options: " . join(" ", %options) if %options;

    my $code = shift @args;

    error "Too many arguments to brew_without() call" if @args;

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

    {
	# XXX hack: setenv+unsetenv do not have a quiet options, so make info() temporarily silent
	local *Doit::Log::info = $quiet ? sub {} : \&Doit::Log::info;
	$self->setenv(PATH => $new_path);
	$self->unsetenv($_) for qw(
	    HOMEBREW_PREFIX
	    HOMEBREW_CELLAR
	    HOMEBREW_REPOSITORY
	);
    }

    $code->();
}

1;

__END__
