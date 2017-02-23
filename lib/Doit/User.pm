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

package Doit::User;

use strict;
use warnings;
our $VERSION = '0.01';

use Exporter 'import';
our @EXPORT_OK = qw(as_user);

{
    my(%uid_cache, %gid_cache, %homedir_cache);

    sub as_user (&$;@) {
	my($code, $user, %opts) = @_;
	my $cache = exists $opts{cache} ? delete $opts{cache} : 1;
	die "Unhandled options: " . join(" ", %opts) if %opts;

	if ($> != 0) {
	    die "as_user works only for root";
	}

	my($uid, $gid, $homedir);
	if ($cache) {
	    ($uid, $gid, $homedir) = ($uid_cache{$user}, $gid_cache{$user}, $homedir_cache{$user});
	}
	if (!defined $uid || !defined $gid || !defined $homedir) {
	    ($uid, $gid, $homedir) = ((getpwnam $user)[2,3,7]);
	    if (!defined $uid) {
		die "Cannot get uid of user '$user'";
	    }
	    ($gid) = $gid =~ m{^(\d+)}; # only the first one
	    if ($cache) {
		$uid_cache{$user}     = $uid;
		$gid_cache{$user}     = $gid;
		$homedir_cache{$user} = $homedir;
	    }
	}

	local $( = $gid; # change first the gid, then the uid!
	local $) = $gid;
	local $< = $uid;
	local $> = $uid;
	local $ENV{HOME} = $homedir;

	$code->();
    }
}

1;

__END__
