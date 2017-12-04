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
$VERSION = '0.03';

use Exporter 'import';
use vars qw(@EXPORT);
@EXPORT = qw(get_sudo module_exists is_dir_eq);

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

sub in_linux_container ($) {
    my($doit) = @_;
    if (open my $fh, "/proc/1/cgroup") {
	while(<$fh>) {
	    chomp;
	    my(undef, undef, $path) = split /:/;
	    if ($path ne '/') {
		# typically /docker or /lxc
		return 1;
	    }
	}
    }
    return 0;
}

# REPO BEGIN
# REPO NAME module_exists /home/slaven.rezic/src/srezic-repository 
# REPO MD5 1ea9ee163b35d379d89136c18389b022

#=head2 module_exists($module)
#
#Return true if the module exists in @INC or if it is already loaded.
#
#=cut

sub module_exists {
    my($filename) = @_;
    $filename =~ s{::}{/}g;
    $filename .= ".pm";
    return 1 if $INC{$filename};
    foreach my $prefix (@INC) {
	my $realfilename = "$prefix/$filename";
	if (-r $realfilename) {
	    return 1;
	}
    }
    return 0;
}
# REPO END

sub is_dir_eq ($$;$) {
    my($dir1, $dir2, $testname) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    if ($dir1 eq $dir2) {
	Test::More::pass($testname);
    } else {
	if ($^O eq 'MSWin32' && defined &Win32::GetShortPathName) {
	    Test::More::is(Win32::GetShortPathName($dir1), Win32::GetShortPathName($dir2), $testname);
	} else {
	    Test::More::is($dir1, $dir2, $testname); # fails;
	}
    }
}

1;

__END__
