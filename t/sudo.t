#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use Test::More;

use Doit;
use Doit::Extcmd qw(is_in_path);

sub run {
    my $d = shift;
    chomp(my $res = `id -u`);
    $res;
}

sub pwinfo {
    getpwuid($<);
}

sub stdout_test {
    print "This goes to STDOUT\n";
    4711;
}

sub stderr_test {
    print STDERR "This goes to STDERR\n";
    314;
}

return 1 if caller;

if (!is_in_path('sudo')) {
    plan skip_all => 'git not in PATH';
}

my $d = Doit->init;
my $sudo = $d->do_sudo(sudo_opts => ['-n'], debug => 0);
my $res = eval { $sudo->call('run') };

plan skip_all => "Cannot run sudo password-less" if $@;
plan 'no_plan';

isa_ok $sudo, 'Doit::Sudo';
is $res, 0, 'switched to uid=0';

my(@pwinfo) = $sudo->call('pwinfo');
is $pwinfo[0], 'root';

is $sudo->call('stdout_test'), 4711;
is $sudo->call('stderr_test'), 314;

## XXX does not work, probably because refs cannot be serialized
#{
#    my $res = $sudo->run(['perl', '-e', 'print "STDOUT without newline"'], '>', \my $stdout);
#    # XXX what's $res supposed to be?
#    is $stdout, 'STDOUT without newline';
#}
#
#{
#    my $res = $sudo->run(['perl', '-e', 'print STDERR "STDERR without newline"'], '>', \my $stderr);
#    # XXX what's $res supposed to be?
#    is $stderr, 'STDERR without newline';
#}

$sudo->exit;

__END__
