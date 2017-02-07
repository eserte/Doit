#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use FindBin;
use lib ("$FindBin::RealBin/../lib");
use Doit;

return 1 if caller;

my $doit = Doit->init;
my $remote = $doit->do_ssh_connect("cvrsnica", debug => 1);
my $cmd = q{echo $(hostname; echo -n ": "; date)};
$doit->system($cmd);
$remote->system($cmd);
$remote->mkdir("/tmp/doit-created");
$remote->system("ls -ald /tmp/doit*");
#$remote->exit;

__END__
