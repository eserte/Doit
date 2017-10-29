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

package TestUtil;

use strict;
use vars qw($VERSION);
$VERSION = '0.01';

use Exporter 'import';
use vars qw(@EXPORT);
@EXPORT = qw(get_sudo);

use Doit::Log;

sub get_sudo ($;@) {
    my($doit, %opts) = @_;
    my $info_ref = delete $opts{info};
    my $debug = delete $opts{debug} || 0;
    my @sudo_opts = @{ delete $opts{sudo_opts} || [] };
    error "Unhandled options: " . join(" ", %opts) if %opts;

    my $sudo = eval { $doit->do_sudo(sudo_opts => ['-n', @sudo_opts], debug => $debug) };
    if (!$sudo) {
	$info_ref->{error} = 'cannot run sudo password-less, or sudo is not available at all' if $info_ref;
	return undef;
    }

    my $res = eval { $sudo->system('perl', '-e', 1); 1 };
    if (!$res) {
	$info_ref->{error} = 'cannot run sudo for other reasons' if $info_ref;
	return undef;
    }

    $sudo;
}

1;

__END__
