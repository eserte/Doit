#!/usr/bin/perl -w
# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2024 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# WWW:  https://github.com/eserte/Doit
#

use strict;
use warnings;
use File::Spec;
use Test::More;

plan skip_all => 'IPC::Run required' if !eval { require IPC::Run; 1 };
plan tests => 3;

for my $doit_trace (1, 0) {
    local $ENV{DOIT_TRACE} = $doit_trace;
    local $ENV{TERM} = undef; # avoid coloring
    IPC::Run::run([$^X, '-MDoit', '-e', <<'EOF'],
my $d = Doit->init;
$d->system("echo", "hello world");
$d->setenv(DOIT_SOME_OBSCURE_ENV_VAR => q{42});
EOF
		  '2>', \my $log, '>', File::Spec->devnull);
    if ($doit_trace) {
	like $log, qr{\QTRACE: cmd_system echo hello world},             'found trace calls (system)';
	like $log, qr{\QTRACE: cmd_setenv DOIT_SOME_OBSCURE_ENV_VAR 42}, 'found trace calls (setenv)';
    } else {
	unlike $log, qr{TRACE}, 'no tracing with unset DOIT_TRACE';
    }
}
