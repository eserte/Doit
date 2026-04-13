#!/usr/bin/perl -w
# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2017,2024,2025,2026 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# WWW:  https://github.com/eserte/Doit
#

use File::Basename qw(basename);
use File::Glob qw(bsd_glob);
use Test::More;

use Doit;
use Doit::Log;

my $d = Doit->init;
$d->add_component('brew');

plan skip_all => "No homebrew available" if !$d->can_brew;
plan 'no_plan';

if (0) {
    # activate if homebrew needs an update before
    $d->system(qw(brew update));
}

{
    my @components = @{ $d->{components} };
    is($components[0]->{relpath}, 'Doit/Brew.pm');
}

{
    my @missing_packages = $d->brew_missing_packages('this-does-not-exist');
    is_deeply(\@missing_packages, ['this-does-not-exist']);
}

my $cellar = $d->brew_get_cellar;
ok defined $cellar, 'found a brew cellar';
ok -d $cellar, "brew cellar $cellar is a directory";

{
    my($package) = bsd_glob("$cellar/*");
    if ($package) {
	$package = basename $package;
	my @missing_packages = $d->brew_missing_packages($package);
	is_deeply(\@missing_packages, []);
    }
}

if ($ENV{GITHUB_ACTIONS}) {
    my $test_package = 'hello';
    $d->brew_install_packages($test_package);
    my @missing_packages = $d->brew_missing_packages($test_package);
    is_deeply(\@missing_packages, []);
    ok !$d->brew_install_packages($test_package), 'no packages to be installed';
    my $fully_qualified_name = "homebrew/core/$test_package";
    ok !$d->brew_install_packages($fully_qualified_name), "no packages to be installed, using fully qualified name ($fully_qualified_name)";
}

$d->brew_without(sub {
		     ok !$d->which('brew'), 'brew command not found within brew_without'
			 or diag "path is $ENV{PATH}";
		     ok !defined $ENV{HOMEBREW_CELLAR}, 'a homebrew-specific environment variable is unset';
		 });

$d->brew_without({quiet=>1},
		 sub {
		     ok !$d->which('brew'), 'brew command not found within brew_without (quiet)'
			 or diag "path is $ENV{PATH}";
		     ok !defined $ENV{HOMEBREW_CELLAR}, 'a homebrew-specific environment variable is unset (quiet)';
		     info "This info should appear!";
		 });

__END__
