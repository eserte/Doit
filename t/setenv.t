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
    $doit->setenv(TEST_SETENV => 2);
    is $ENV{TEST_SETENV}, 2, 'value was changed (previously had other value)';
    $doit->setenv(TEST_SETENV => 2);
    is $ENV{TEST_SETENV}, 2, 'value was not changed';
    $doit->unsetenv('TEST_SETENV');
    ok !exists $ENV{TEST_SETENV}, 'value was deleted';
}

{
    local $ENV{TEST_SETENV};
    $doit->setenv(TEST_SETENV => 1);
    is $ENV{TEST_SETENV}, 1, 'value wa changed (from previously non-existent)';
}

__END__
