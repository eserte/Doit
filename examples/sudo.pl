#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use FindBin;
use lib ("$FindBin::RealBin/../lib");
use Doit;

sub hello {
    warn "I am " . getpwuid($<);
}

sub something {
    warn "else...";
}

return 1 if caller;

my $doit = Doit->init;
my $remote = $doit->do_sudo; # (sudo_opts => ['-u', '#'.$<]);
#my $cmd = q{echo $(hostname; echo -n ": "; date)};
#$doit->system($cmd);
$doit->call("hello");
#$remote->system($cmd);
#$remote->system("id");
$remote->call("hello");
$remote->call("something");
warn $remote->exit;

__END__
