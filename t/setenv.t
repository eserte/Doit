#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use Doit;
use Test::More;

plan 'no_plan';

my $doit = Doit->init;

{
    local $ENV{TEST_SETENV} = 1;
    is $doit->setenv(TEST_SETENV => 2), 1;
    is $ENV{TEST_SETENV}, 2, 'value was changed (previously had other value)';
    is $doit->setenv(TEST_SETENV => 2), 0;
    is $ENV{TEST_SETENV}, 2, 'value was not changed';
    $doit->unsetenv('TEST_SETENV'), 1;
    ok !exists $ENV{TEST_SETENV}, 'value was deleted';
    $doit->unsetenv('TEST_SETENV'), 0; # noop
}

{
    local $ENV{TEST_SETENV};
    is $doit->setenv(TEST_SETENV => 1), 1;
    is $ENV{TEST_SETENV}, 1, 'value was changed (from previously non-existent)';
}

{
    my $dryrun_doit = $doit->{Doit}->dryrunner;
    local $ENV{TEST_SETENV} = 0;
    is $dryrun_doit->setenv(TEST_SETENV => 1), 1;
    is $ENV{TEST_SETENV}, 0, 'value is still unchanged in dry-run mode';
    $dryrun_doit->unsetenv('TEST_SETENV');
    is $ENV{TEST_SETENV}, 0, 'value is still there after an unsetenv in dry-run mode';
}

__END__
