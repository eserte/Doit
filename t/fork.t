#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use Test::More 'no_plan';

sub run_test {
    my(undef, $a, $b) = @_;
    $a + $b;
}

sub forked_pid {
    $$;
}

return 1 if caller;

use Doit;

no warnings 'once'; # cease usage of $Doit::Fork::... globals; call after "use Doit" because of implicit "use warnings"

my $d = Doit->init;
my $fork = $d->do_fork;
isa_ok $fork, 'Doit::Fork';

is $Doit::Fork::keep_last_exits, 10, 'default value for $keep_last_exits, available after running do_fork first';
is_deeply \@Doit::Fork::last_exits, [], '@last_exits is empty';

is $fork->qx($^X, "-e", 'print 1+1, "\n"'), "2\n", "run external command in fork";
is $fork->call_with_runner('run_test', 2, 2), 4, "run function in fork";
isnt $fork->call_with_runner('forked_pid'), $$, 'forked process is really another process';
is $fork->{pid}, $fork->call_with_runner('forked_pid'), '$fork->{pid} with expected value';

my $forked_pid = $fork->{pid}; # used later
undef $fork;
#use Doit::Log; info $Doit::Fork::last_exits[-1]->{msg};

is scalar(@Doit::Fork::last_exits), 1, 'there is one reaped process';
is $Doit::Fork::last_exits[0]->{pid}, $forked_pid, 'expected pid';
is $Doit::Fork::last_exits[0]->{exitcode}, 0, 'expected exit code';
is $Doit::Fork::last_exits[0]->{msg}, "Command exited with exit code 0", 'expected msg';

__END__
