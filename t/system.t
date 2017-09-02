#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use Test::More;

plan skip_all => "Signals are problematic on Windows" if $^O eq 'MSWin32';
plan 'no_plan';

use Doit;

my $r = Doit->init;

$r->system('true');
pass 'no exception';

SKIP: {
    skip "Requires Capture::Tiny", 1
	if !eval { require Capture::Tiny; 1 };
    my $save_pwd = save_pwd2();
    chdir "/";
    my($stdout, $stderr) = Capture::Tiny::capture
	(sub {
	     $r->system({show_cwd=>1}, 'echo', 'hello');
	 });
    is $stdout, "hello\n";
    like $stderr, qr{INFO:.*echo hello \(in /\)};
}

eval { $r->system('false') };
like $@, qr{^Command exited with exit code 1};
is $@->{exitcode}, 1;

eval { $r->system($^X, '-e', 'kill TERM => $$') };
like $@, qr{^Command died with signal 15, without coredump};
is $@->{signalnum}, 15;
is $@->{coredump}, 'without';

eval { $r->system($^X, '-e', 'kill KILL => $$') };
like $@, qr{^Command died with signal 9, without coredump};
is $@->{signalnum}, 9;
is $@->{coredump}, 'without';

SKIP: {
    skip "No BSD::Resource available", 1
	if !eval { require BSD::Resource; 1 };
    skip "coredumps disabled", 1
	if BSD::Resource::getrlimit(BSD::Resource::RLIMIT_CORE()) < 4096; # minimum of 4k needed on linux to actually do coredumps
    eval { $r->system($^X, '-e', 'kill ABRT => $$') };
    like $@, qr{^Command died with signal 6, with coredump};
    is $@->{signalnum}, 6;
    is $@->{coredump}, 'with';
}

# REPO BEGIN
# REPO NAME save_pwd2 /home/eserte/src/srezic-repository 
# REPO MD5 d0ad5c46f2276dc8aff7dd5b0a83ab3c

BEGIN {
    sub save_pwd2 {
	require Cwd;
	my $pwd = Cwd::getcwd();
	if (!defined $pwd) {
	    warn "No known current working directory";
	}
	bless {cwd => $pwd}, __PACKAGE__ . '::SavePwd2';
    }
    my $DESTROY = sub {
	my $self = shift;
	if (defined $self->{cwd}) {
	    chdir $self->{cwd}
	        or die "Can't chdir to $self->{cwd}: $!";
	}
    };
    no strict 'refs';
    *{__PACKAGE__.'::SavePwd2::DESTROY'} = $DESTROY;
}
# REPO END

__END__
