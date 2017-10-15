#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

# Check if the exit code of Doit one-liners and scripts is as
# expected.

use Doit;
use File::Temp 'tempfile';
use Test::More 'no_plan';

my $doit = Doit->init;

{
    $doit->system($^X, '-MDoit', '-e', q{Doit->init->system($^X, '-e', 'exit 0')});
    pass 'passing Doit one-liner';
}

{
    eval { $doit->system($^X, '-MDoit', '-e', q{Doit->init->system($^X, '-e', 'exit 1')}) };
    is $@->{exitcode}, 1, 'failing Doit one-liner';
}

{
    my($tmpfh,$tmpfile) = tempfile(UNLINK => 1, SUFFIX => '_doit.pl');
    print $tmpfh <<'EOF';
use Doit;
Doit->init->system($^X, '-e', 'exit 0');
EOF
    close $tmpfh or die $!;
    $doit->chmod(0755, $tmpfile);
    $doit->system($^X, $tmpfile);
    pass 'passing Doit script';
}

{
    my($tmpfh,$tmpfile) = tempfile(UNLINK => 1, SUFFIX => '_doit.pl');
    print $tmpfh <<'EOF';
use Doit;
Doit->init->system($^X, '-e', 'exit 1');
EOF
    close $tmpfh or die $!;
    $doit->chmod(0755, $tmpfile);
    eval { $doit->system($^X, $tmpfile) };
    is $@->{exitcode}, 1, 'failing Doit script';
}

__END__
