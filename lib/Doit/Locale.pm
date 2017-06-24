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

package Doit::Locale;

use strict;
use warnings;
use vars qw($VERSION);
$VERSION = '0.01';

use Doit::Log;

sub new { bless {}, shift }
sub functions { qw(locale_enable_locale) }

sub locale_enable_locale {
    my($self, $locale) = @_;
    my %locale;
    if (ref $locale eq 'ARRAY') {
	%locale = map{($_,1)} @$locale;
    } else {
	%locale = ($locale => 1);
    }
    open my $fh, '-|', 'locale', '-a'
	or error "Error while running 'locale -a': $!";
    while(<$fh>) {
	chomp;
	if ($locale{$_}) {
	    return 0;
	}
    }
    close $fh
	or error "Error while running 'locale -a': $!";

    if (!-e "/etc/locale.gen") { # Debian and Debian-lie
	error "Don't know how to enable locales on this system";
    }

    my $all_locales = '(' . join('|', map { quotemeta $_ } keys %locale) . ')';
    my $changes = $self->change_file("/etc/locale.gen",
				     {match  => qr{^#\s+$all_locales(\s|$)},
				      action => sub { $_[0] =~ s{^#\s+}{}; },
				     },
				    );
    if (!$changes) {
	error "Cannot find prepared locale '$locale' in /etc/locale.gen";
    }

    $self->system('locale-gen');

    1;
}

1;

__END__
