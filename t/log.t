#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use Test::More;
BEGIN {
    plan skip_all => 'No Capture::Tiny available' if !eval { require Capture::Tiny; Capture::Tiny->import('capture'); 1 };
    plan skip_all => 'No Term::ANSIColor available' if !eval { require Term::ANSIColor; Term::ANSIColor->import('colorstrip'); 1 };
}

use Doit;
use Doit::Log qw(info warning error); # "note" unfortunately collides with Test::More's note

plan 'no_plan';

my($stdout, $stderr);

($stdout, $stderr) = capture {
    info "info message";
};
is $stdout, '';
is colorstrip($stderr), "INFO: info message\n";

($stdout, $stderr) = capture {
    Doit::Log::note "note message";
};
is $stdout, '';
is colorstrip($stderr), "NOTE: note message\n";

($stdout, $stderr) = capture {
    warning "warning message";
};
is $stdout, '';
is colorstrip($stderr), "WARN: warning message\n";

eval {
    error "error message";
};
like colorstrip($@), qr{^ERROR: error message at .* line \d+\.\n\z};

__END__
