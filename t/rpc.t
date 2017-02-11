#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use Test::More 'no_plan';

use IO::Pipe;

use Doit;

sub get_pid { $$ }
sub get_random_numbers { map { int(rand(10)) } (1..10) }

my $to_remote_pipe = IO::Pipe->new;
my $from_remote_pipe = IO::Pipe->new;

my $pid = fork;
die $! if !defined $pid;
if ($pid == 0) {
    $to_remote_pipe->reader;
    $from_remote_pipe->writer;
    Doit::RPC->new(Doit->init, $to_remote_pipe, $from_remote_pipe)->run;
    exit;
}
$to_remote_pipe->writer;
$from_remote_pipe->reader;
my $rpc = Doit::RPC->new(undef, $from_remote_pipe, $to_remote_pipe);
isa_ok $rpc, 'Doit::RPC';

my($got_pid) = $rpc->call_remote(qw(call get_pid)); # XXX context not right yet
is $got_pid, $pid, 'got pid of remote worker';

my @random_numers = $rpc->call_remote(qw(call get_random_numbers));
is scalar(@random_numers), 10;

my($got_bye) = $rpc->call_remote('exit');
is $got_bye, 'bye-bye'; # XXX really?

waitpid $pid, 0; # should not hang

__END__
