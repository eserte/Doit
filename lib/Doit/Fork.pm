# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2017,2023,2024 Slaven Rezic. All rights reserved.
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
# WWW:  http://www.rezic.de/eserte/
#

package Doit::Fork;

use Doit;

use strict;
use warnings;
our $VERSION = '0.03';

use vars '@ISA'; @ISA = ('Doit::_AnyRPCImpl');

use Doit::Log;

our @last_exits;
our $keep_last_exits; $keep_last_exits = 10 if !defined $keep_last_exits;

sub new { bless {}, shift }
sub functions { qw() }

sub do_connect {
    my($class, %opts) = @_;

    my $dry_run = delete $opts{dry_run};
    my $debug = delete $opts{debug};
    die "Unhandled options: " . join(" ", %opts) if %opts;

    my $self = bless { }, $class;

    my $d;
    if ($debug) {
	$d = sub ($) {
	    Doit::Log::info("PARENT: $_[0]");
	};
    } else {
	$d = sub ($) { };
    }
    $self->{d} = $d;

    require IO::Pipe;
    my $pipe_to_fork   = IO::Pipe->new;
    my $pipe_from_fork = IO::Pipe->new;
    my $worker_pid = fork;
    if (!defined $worker_pid) {
	error "fork failed: $!";
    } elsif ($worker_pid == 0) {
	my $d = do {
	    local @ARGV = $dry_run ? '--dry-run' : ();
	    Doit->init;
	};
	$pipe_to_fork->reader;
	$pipe_from_fork->writer;
	$pipe_from_fork->autoflush(1);
	Doit::RPC::PipeServer->new($d, $pipe_to_fork, $pipe_from_fork, debug => $debug)->run;
	CORE::exit(0);
    }

    $d->("Forked worker $worker_pid...");

    $pipe_to_fork->writer;
    $pipe_from_fork->reader;
    $self->{rpc} = Doit::RPC::Client->new($pipe_from_fork, $pipe_to_fork, label => "fork:", debug => $debug);
    $self->{pid} = $worker_pid;

    $self;
}

sub DESTROY {
    my $self = shift;
    # Note: if new() is called without followed by do_connect(), then no {pid} is set
    if (defined $self->{pid}) {
	$self->{d}->("About to destroy fork with pid $self->{pid}...");
    }
    delete $self->{rpc};
    if (defined $self->{pid}) {
	$self->{d}->(" reap child process");
	waitpid $self->{pid}, 0;
	my %exit_res = Doit::_analyze_dollar_questionmark();
	$exit_res{pid} = $self->{pid};
	push @last_exits, \%exit_res;
	if (defined $keep_last_exits) {
	    while (@last_exits > $keep_last_exits) {
		shift @last_exits;
	    }
	}
    }
}

{
    package Doit::RPC::PipeServer;
    use vars '@ISA'; @ISA = ('Doit::RPC');

    sub new {
	my($class, $runner, $pipe_to_server, $pipe_from_server, %options) = @_;

	my $debug = delete $options{debug};
	die "Unhandled options: " . join(" ", %options) if %options;

	bless {
	       runner           => $runner,
	       pipe_to_server   => $pipe_to_server,
	       pipe_from_server => $pipe_from_server,
	       debug            => $debug,
	      }, $class;
    }

    sub run {
	my($self) = @_;

	my $d;
	if ($self->{debug}) {
	    $d = sub ($) {
		Doit::Log::info("WORKER: $_[0]");
	    };
	} else {
	    $d = sub ($) { };
	}

	$d->("Start worker ($$)...");
	my $pipe_to_server = $self->{pipe_to_server};
	my $pipe_from_server = $self->{pipe_from_server};

	$self->{infh}  = $pipe_to_server;
	$self->{outfh} = $pipe_from_server;
	while () {
	    $d->(" waiting for line from comm");
	    my($context, @data) = $self->receive_data;
	    if (!defined $context) {
		$d->(" got eof");
		$pipe_to_server->close;
		$pipe_from_server->close;
		return;
	    } elsif ($data[0] =~ m{^exit$}) {
		$d->(" got exit command");
		$self->send_data('r', 'bye-bye');
		$pipe_to_server->close;
		$pipe_from_server->close;
		return;
	    }
	    $d->(" calling method $data[0]");
	    my($rettype, @ret) = $self->{runner}->call_wrapped_method($context, @data);
	    $d->(" sending result back");
	    $self->send_data($rettype, @ret);
	}
    }
}

1;

__END__
