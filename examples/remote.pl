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
    require Sys::Hostname;
    warn "This runs somewhere: " . Sys::Hostname::hostname();
}

return 1 if caller;

my $doit = Doit->init;
my $remote = $doit->do_ssh_connect("eserte.dev4.bbbike.org", debug => 1, as => "root");
my $cmd = q{echo $(hostname; echo -n ": "; date)};
$doit->system($cmd);
$doit->call("hello");
$remote->system($cmd);
$remote->system("id");
$remote->call("hello");
#$remote->exit;

__END__
