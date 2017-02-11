#!/usr/bin/perl -w
# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2017 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
# WWW:  http://www.rezic.de/eserte/
#

use strict;

{
    package Doit;

    sub new {
	my $class = shift;
	my $self = bless { }, $class;
	# XXX hmmm, creating now self-refential data structures ...
	$self->{runner}    = Doit::Runner->new($self);
	$self->{dryrunner} = Doit::Runner->new($self, 1);
	$self;
    }
    sub runner    { shift->{runner} }
    sub dryrunner { shift->{dryrunner} }

    sub init {
	my($class) = @_;
	require Getopt::Long;
	Getopt::Long::Configure('pass_through');
	Getopt::Long::GetOptions('dry-run|n' => \my $dry_run);
	Getopt::Long::Configure('no_pass_through'); # XXX or restore old value?
	my $doit = $class->new;
	if ($dry_run) {
	    $doit->dryrunner;
	} else {
	    $doit->runner;
	}
    }

    sub install_generic_cmd {
	my($self, $name, $check, $code, $msg) = @_;
	if (!$msg) {
	    $msg = sub { my($self, $args) = @_; $name . ($args ? " @$args" : '') };
	}
	my $cmd = sub {
	    my($self, @args) = @_;
	    my @commands;
	    my $addinfo = {};
	    if ($check->($self, \@args, $addinfo)) {
		push @commands, {
				 code => sub { $code->($self, \@args, $addinfo) },
				 msg  => $msg->($self, \@args, $addinfo),
				};
	    }
	    Doit::Commands->new(@commands);
	};
	no strict 'refs';
	*{"cmd_$name"} = $cmd;
    }

    sub _copy_stat {
	my($src, $dest) = @_;
	my @stat = ref $src eq 'ARRAY' ? @$src : stat($src);
	die "Can't stat $src: $!" if !@stat;

	chmod $stat[2], $dest
	    or warn "Can't chmod $dest to " . sprintf("0%o", $stat[2]) . ": $!";
	chown $stat[4], $stat[5], $dest
	    or do {
		my $save_err = $!; # otherwise it's lost in the get... calls
		warn "Can't chown $dest to " .
		    (getpwuid($stat[4]))[0] . "/" .
		    (getgrgid($stat[5]))[0] . ": $save_err";
	    };
	utime $stat[8], $stat[9], $dest
	    or warn "Can't utime $dest to " .
	    scalar(localtime $stat[8]) . "/" .
	    scalar(localtime $stat[9]) .
	    ": $!";
    }

    sub cmd_chmod {
	my($self, $mode, @files) = @_;
	my @files_to_change;
	for my $file (@files) {
	    my @s = stat($file);
	    if (@s) {
		if (($s[2] & 07777) != $mode) {
		    push @files_to_change, $file;
		}
	    }
	}
	my @commands;
	if (@files_to_change) {
	    push @commands, {
			     code => sub { chmod $mode, @files_to_change or die $! },
			     msg  => sprintf "chmod 0%o %s", $mode, join(" ", @files_to_change), # shellquote?
			    };
	}
	Doit::Commands->new(@commands);
    }

    sub cmd_chown {
	my($self, $uid, $gid, @files) = @_;

	if (!defined $uid) {
	    $uid = -1;
	} elsif ($uid !~ /^-?\d+$/) {
	    my $_uid = (getpwnam $uid)[2];
	    if (!defined $_uid) {
		# XXX problem: in dry-run mode the user/group could be
		# created in _this_ pass, so this error would happen
		# while in wet-run everything would be fine. Good solution?
		# * do uid/gid resolution _again_ in the command if it failed here?
		# * maintain a virtual list of created users/groups while this run, and
		#   use this list as a fallback?
		die "User '$uid' does not exist";
	    }
	    $uid = $_uid;
	}
	if (!defined $gid) {
	    $gid = -1;
	} elsif ($gid !~ /^-?\d+$/) {
	    my $_gid = (getpwnam $gid)[2];
	    if (!defined $_gid) {
		die "Group '$gid' does not exist";
	    }
	    $gid = $_gid;
	}

	my @files_to_change;
	if ($uid != -1 || $gid != -1) {
	    for my $file (@files) {
		my @s = stat($file);
		if (@s) {
		    if ($uid != -1 && $s[4] != $uid) {
			push @files_to_change, @files;
		    } elsif ($gid != -1 && $s[5] != $gid) {
			push @files_to_change, @files;
		    }
		}
	    }
	}

	my @commands;
	if (@files_to_change) {
	    push @commands, {
			     code => sub { chown $uid, $gid, @files_to_change or die $! },
			     msg  => "chown $uid, $gid, @files_to_change", # shellquote?
			    };
	}
	
	Doit::Commands->new(@commands);
    }

    sub cmd_cond_run {
	my($self, %opts) = @_;
	my $if      = delete $opts{if};
	my $unless  = delete $opts{unless};
	my $creates = delete $opts{creates};
	my $cmd     = delete $opts{cmd};
	die "Unhandled options: " . join(" ", %opts) if %opts;

	my $doit = 1;
	if ($if && !$if->()) {
	    $doit = 0;
	}
	if ($doit && $unless && $unless->()) {
	    $doit = 0;
	}
	if ($doit && $creates && -e $creates) {
	    $doit = 0;
	}

	if ($doit) {
	    $self->cmd_run(@$cmd);
	} else {
	    Doit::Commands->new();
	}
    }

    sub cmd_make_path {
	my($self, @directories) = @_;
	my $options = {}; if (ref $directories[-1] eq 'HASH') { $options = pop @directories }
	my @directories_to_create = grep { !-d $_ } @directories;
	my @commands;
	if (@directories_to_create) {
	    push @commands, {
			     code => sub {
				 require File::Path;
				 File::Path::make_path(@directories_to_create, $options)
					 or die $!;
			     },
			     msg => "make_path @directories",
			    };
	}
	Doit::Commands->new(@commands);
    }

    sub cmd_mkdir {
	my($self, $directory, $mask) = @_;
	my @commands;
	if (!-d $directory) {
	    if (defined $mask) {
		push @commands, {
				 code => sub { mkdir $directory, $mask or die $! },
				 msg  => "mkdir $directory with mask $mask",
				};
	    } else {
		push @commands, {
				 code => sub { mkdir $directory or die $! },
				 msg  => "mkdir $directory",
				};
	    }
	}
	Doit::Commands->new(@commands);
    }

    sub cmd_remove_tree {
	my($self, @directories) = @_;
	my $options = {}; if (ref $directories[-1] eq 'HASH') { $options = pop @directories }
	my @directories_to_remove = grep { -d $_ } @directories;
	my @commands;
	if (@directories_to_remove) {
	    push @commands, {
			     code => sub {
				 require File::Path;
				 File::Path::remove_tree(@directories_to_remove, $options)
					 or die $!;
			     },
			     msg => "remove_tree @directories_to_remove",
			    };
	}
	Doit::Commands->new(@commands);
    }

    sub cmd_rename {
	my($self, $from, $to) = @_;
	my @commands;
	push @commands, {
			 code => sub { rename $from, $to or die $! },
			 msg  => "rename $from, $to",
			};
	Doit::Commands->new(@commands);
    }

    sub cmd_copy {
	my($self, $from, $to) = @_;
	my @commands;
	if (!-e $to || do { require File::Compare; File::Compare::compare($from, $to) != 0 }) {
	    push @commands, {
			     code => sub {
				 require File::Copy;
				 File::Copy::copy($from, $to)
					 or die "Copy failed: $!";
			     },
			     msg => "copy $from $to",
			    };
	}
	Doit::Commands->new(@commands);
    }

    sub cmd_move {
	my($self, $from, $to) = @_;
	my @commands = {
			code => sub {
			    require File::Copy;
			    File::Copy::move($from, $to)
				    or die "Move failed: $!";
			},
			msg => "move $from $to",
		       };
	Doit::Commands->new(@commands);
    }

    sub cmd_rmdir {
	my($self, $directory) = @_;
	my @commands;
	if (-d $directory) {
	    push @commands, {
			     code => sub { rmdir $directory or die $! },
			     msg  => "rmdir $directory",
			    };
	}
	Doit::Commands->new(@commands);
    }

    sub cmd_run {
	my($self, @args) = @_;
	my @commands;
	push @commands, {
			 code => sub {
			     require IPC::Run;
			     my $success = IPC::Run::run(@args);
			     die if !$success;
			 },
			 msg  => do {
			     my @print_cmd;
			     for my $arg (@args) {
				 if (ref $arg eq 'ARRAY') {
				     push @print_cmd, @$arg;
				 } else {
				     push @print_cmd, $arg;
				 }
			     }
			     join " ", @print_cmd;
			 },
			};
	Doit::Commands->new(@commands);
    }

    sub cmd_symlink {
	my($self, $oldfile, $newfile) = @_;
	my $doit;
	if (-l $newfile) {
	    my $points_to = readlink $newfile
		or die "Unexpected: readlink $newfile failed (race condition?)";
	    if ($points_to ne $oldfile) {
		$doit = 1;
	    }
	} elsif (!-e $newfile) {
	    $doit = 1;
	} else {
	    warn "$newfile exists but is not a symlink, will fail later...";
	}
	my @commands;
	if ($doit) {
	    push @commands, {
			     code => sub { symlink $oldfile, $newfile or die $! },
			     msg  => "symlink $oldfile $newfile",
			    };
	}
	Doit::Commands->new(@commands);
    }

    sub cmd_system {
	my($self, @args) = @_;
	my @commands;
	push @commands, {
			 code => sub { system @args; die if $? != 0; },
			 msg  => "@args",
			};
	Doit::Commands->new(@commands);
    }

    sub cmd_touch {
	my($self, @files) = @_;
	my @commands;
	for my $file (@files) {
	    if (!-e $file) {
		push @commands, {
				 code => sub { open my $fh, '>>', $file or die $! },
				 msg  => "touch non-existent file $file",
				}
	    } else {
		push @commands, {
				 code => sub { utime time, time, $file or die $! },
				 msg  => "touch existent file $file",
				};
	    }
	}
	Doit::Commands->new(@commands);
    }

    sub cmd_unlink {
	my($self, @files) = @_;
	my @files_to_remove;
	for my $file (@files) {
	    if (-e $file || -l $file) {
		push @files_to_remove, $file;
	    }
	}
	my @commands;
	if (@files_to_remove) {
	    push @commands, {
			     code => sub { unlink @files_to_remove or die $! },
			     msg  => "unlink @files_to_remove", # shellquote?
			    };
	}
	Doit::Commands->new(@commands);
    }

    sub cmd_utime {
	my($self, $atime, $mtime, @files) = @_;
	my $now;
	if (!defined $atime) {
	    $atime = ($now ||= time);
	}
	if (!defined $mtime) {
	    $mtime = ($now ||= time);
	}
	my @commands;
	push @commands, {
			 code => sub { utime $atime, $mtime, @files or die $! },
			 msg  => "utime $atime, $mtime, @files",
			};
	Doit::Commands->new(@commands);
    }

    sub cmd_write_binary {
	my($self, $filename, $content) = @_;

	my $doit;
	my $need_diff;
	if (!-e $filename) {
	    $doit = 1;
	} elsif (-s $filename != length($content)) {
	    $doit = 1;
	    $need_diff = 1;
	} else {
	    open my $fh, '<', $filename
		or die "Can't open $filename: $!";
	    binmode $fh;
	    local $/;
	    my $file_content = <$fh>;
	    if ($file_content ne $content) {
		$doit = 1;
		$need_diff = 1;
	    }
	}

	my @commands;
	if ($doit) {
	    push @commands, {
			     code => sub {
				 open my $ofh, '>', $filename
				     or die "Can't write to $filename: $!";
				 binmode $ofh;
				 print $ofh $content;
				 close $ofh
				     or die "While closing $filename: $!";
			     },
			     msg => do {
				 if ($need_diff) {
				     require IPC::Run;
				     my $diff;
				     IPC::Run::run(['diff', '-u', $filename, '-'], '<', \$content, '>', \$diff);
				     "Replace existing file $filename with diff:\n$diff";
				 } else {
				     "Create new file $filename with content:\n$content";
				 }
			     },
			    };
	}
	Doit::Commands->new(@commands);  
    }

    sub cmd_change_file {
	my($self, $file, @changes) = @_;
	if (!-e $file) {
	    die "$file does not exist";
	}
	if (!-f $file) {
	    die "$file is not a file";
	}

	my @commands;

	for (@changes) {
	    if ($_->{add_if_missing}) {
		my $line = delete $_->{add_if_missing};
		$_->{unless_match} = $line;
		if ($_->{add_after}) {
		    my $add_after = delete $_->{add_after};
		    qr{$add_after}; # must be a regexp
		    $_->{action} = sub {
			my $arrayref = $_[0];
			my $found = 0;
			for my $i (0 .. $#$arrayref) {
			    if ($arrayref->[$i] =~ $add_after) {
				splice @$arrayref, $i+1, 0, $line;
				$found = 1;
				last;
			    }
			}
			if (!$found) {
			    die "Cannot find '$add_after' in file";
			}
		    };
		    delete $_->{add_after};
		} else {
		    $_->{action} = sub { my $arrayref = $_[0]; push @$arrayref, $line };
		}
	    }
	}

	my @match_actions;
	my @unless_match_actions;
	for (@changes) {
	    if ($_->{unless_match}) {
		if (ref $_->{unless_match} ne 'Regexp') {
		    my $rx = '^' . quotemeta($_->{unless_match}) . '$';
		    $_->{unless_match} = qr{$rx};
		}
		if (!$_->{action}) {
		    die "action is missing";
		}
		if (ref $_->{action} ne 'CODE') {
		    die "action must be a sub reference";
		}
		push @unless_match_actions, $_;
	    } elsif ($_->{match}) {
		if (ref $_->{match} ne 'Regexp') {
		    die "match must be a regexp";
		}
		if ($_->{action}) {
		    if (ref $_->{action} ne 'CODE') {
			die "action must be a sub reference";
		    }
		} elsif ($_->{replace}) {
		    # accept
		} else {
		    die "action or replace is missing";
		}
		push @match_actions, $_;
	    } else {
		die "match or unless_match is missing";
	    }
	}

	require File::Temp;
	require File::Basename;
	require File::Copy;
	my($tmfh,$tmpfile) = File::Temp::tempfile('doittemp_XXXXXXXX', UNLINK => 1, DIR => File::Basename::dirname($file));
	File::Copy::copy($file, $tmpfile)
		or die "failed to copy $file to temporary file $tmpfile: $!";
	_copy_stat $file, $tmpfile;

	require Tie::File;
	tie my @lines, 'Tie::File', $tmpfile
	    or die "cannot tie file $file: $!";

	my $no_of_changes = 0;
	for my $match_action (@match_actions) {
	    my $match  = $match_action->{match};
	    for my $line (@lines) {
		if ($line =~ $match) {
		    if (exists $match_action->{replace}) {
			my $replace = $match_action->{replace};
			if ($line ne $replace) {
			    push @commands, { msg => "replace '$line' with '$replace' in '$file'" };
			    $line = $replace;
			    $no_of_changes++;
			}
		    } else {
			push @commands, { msg => "matched '$match' on line '$line' in '$file' -> execute action" };
			my $action = $match_action->{action};
			$action->($line);
			$no_of_changes++;
		    }
		}
	    }
	}
    ITER: for my $unless_match_action (@unless_match_actions) {
	    my $match  = $unless_match_action->{unless_match};
	    for my $line (@lines) {
		if ($line =~ $match) {
		    next ITER;
		}
	    }
	    push @commands, { msg => "did not find '$match' in '$file' -> execute action" };
	    my $action = $unless_match_action->{action};
	    $action->(\@lines);
	    $no_of_changes++;
	}

	if ($no_of_changes) {
	    push @commands, {
			     code => sub {
				 rename $tmpfile, $file
				     or die "Can't rename $tmpfile to $file: $!";
			     },
			     msg => do {
				 require IPC::Run;
				 my $diff;
				 IPC::Run::run(['diff', '-u', $file, $tmpfile], '>', \$diff);
				 "Final changes as diff:\n$diff";
			     }
			    };
	}

	Doit::Commands->new(@commands);
    }

}

{
    package Doit::Commands;
    sub new {
	my($class, @commands) = @_;
	my $self = bless \@commands, $class;
	$self;
    }
    sub commands { @{$_[0]} }
    sub doit {
	my($self) = @_;
	for my $command ($self->commands) {
	    if (exists $command->{msg}) {
		print STDERR "INFO: " . $command->{msg} . "\n";
	    }
	    if (exists $command->{code}) {
		$command->{code}->();
	    }
	}
    }
    sub show {
	my($self) = @_;
	for my $command ($self->commands) {
	    if (exists $command->{msg}) {
		print STDERR "INFO: " . $command->{msg} . " (dry-run)\n";
	    }
	}
    }
}

{
    package Doit::Runner;
    sub new {
	my($class, $X, $dryrun) = @_;
	bless { X => $X, dryrun => $dryrun }, $class;
    }
    sub is_dry_run { shift->{dryrun} }

    sub install_generic_cmd {
	my($self, $name, @args) = @_;
	$self->{X}->install_generic_cmd($name, @args);
	install_cmd($name); # XXX hmmmm
    }

    sub install_cmd ($) {
	my $cmd = shift;
	my $meth = 'cmd_' . $cmd;
	my $code = sub {
	    my($self, @args) = @_;
	    if ($self->{dryrun}) {
		$self->{X}->$meth(@args)->show;
	    } else {
		$self->{X}->$meth(@args)->doit;
	    }
	};
	no strict 'refs';
	*{$cmd} = $code;
    }

    for my $cmd (
		 qw(chmod chown mkdir rename rmdir symlink system unlink utime),
		 qw(make_path remove_tree), # File::Path
		 qw(copy move), # File::Copy
		 qw(run), # IPC::Run
		 qw(cond_run), # conditional run
		 qw(touch), # like unix touch
		 qw(write_binary), # like File::Slurper
		 qw(change_file), # own invention
		) {
	install_cmd $cmd;
    }

    sub call_wrapped_method {
	my($self, $context, $method, @args) = @_;
	my @ret;
	if ($context eq 'a') {
	    @ret    = eval { $self->$method(@args) };
	} else {
	    $ret[0] = eval { $self->$method(@args) };
	}
	if ($@) {
	    ('e', $@);
	} else {
	    ('r', @ret);
	}
    }

    # XXX call vs. call_with_runner ???
    sub call {
	my($self, $sub, @args) = @_;
	$sub = 'main::' . $sub if $sub !~ /::/;
	no strict 'refs';
	&$sub(@args);
    }

    sub call_with_runner {
	my($self, $sub, @args) = @_;
	$sub = 'main::' . $sub if $sub !~ /::/;
	no strict 'refs';
	&$sub($self, @args);
    }

    # XXX does this belong here?
    sub do_ssh_connect {
	my($self, $host, %opts) = @_;
	my $remote = Doit::SSH->do_connect($host, dry_run => $self->is_dry_run, %opts);
	$remote;
    }
}

{
    package Doit::RPC;

    require Storable;
    require IO::Handle;

    # $runner is typically undef on the client, and Doit->init on the server
    sub new {
	my($class, $runner, $infh, $outfh) = @_;
	$infh  ||= \*STDIN;
	$outfh ||= \*STDOUT;
	$outfh->autoflush(1);
	bless {
	       runner => $runner,
	       infh   => $infh,
	       outfh  => $outfh,
	      }, $class;
    }

    # Call on "server"
    sub run {
	my $self = shift;
	while() {
	    my($context, @data) = $self->receive_data;
	    if ($data[0] =~ m{^exit$}) {
		$self->send_data('r', 'bye-bye');
		return;
	    }
	    open my $oldout, ">&STDOUT" or die $!;
	    open STDOUT, '>', "/dev/stderr" or die $!; # XXX????
	    my($rettype, @ret) = $self->{runner}->call_wrapped_method($context, @data);
	    open STDOUT, ">&", $oldout or die $!;
	    $self->send_data($rettype, @ret);
	}
    }

    # Call for every command on client
    sub call_remote {
	my($self, @args) = @_;
	my $context = wantarray ? 'a' : 's'; # XXX more possible context (void...)?
	$self->send_data($context, @args);
	my($rettype, @ret) = $self->receive_data(@args);
	if ($rettype eq 'e') {
	    die $ret[0];
	} elsif ($rettype eq 'r') {
	    if ($context eq 'a') {
		return @ret;
	    } else {
		return $ret[0];
	    }
	} else {
	    die "Unexpected return type '$rettype' (should be 'e' or 'r')";
	}
    }

    sub receive_data {
	my($self) = @_;
	my $fh = $self->{infh};
	my $buf;
	read $fh, $buf, 4 or die "receive_data failed (getting length): $!";
	my $length = unpack("N", $buf);
	read $fh, $buf, $length or die "receive_data failed (getting data): $!";
	@{ Storable::thaw($buf) };
    }

    sub send_data {
	my($self, @cmd) = @_;
	my $fh = $self->{outfh};
	my $data = Storable::nfreeze(\@cmd);
	print $fh pack("N", length($data)) . $data;
    }
}

{
    package Doit::SSH;

    sub do_connect {
	require File::Basename;
	require Net::OpenSSH;
	my($class, $host, %opts) = @_;
	my $dry_run = delete $opts{dry_run};
	my $debug = delete $opts{debug};
	my $as = delete $opts{as};
	die "Unhandled options: " . join(" ", %opts) if %opts;

	my $self = bless { host => $host }, $class;
	my $ssh = Net::OpenSSH->new($host);
	$ssh->error and die "Connection error to $host: " . $ssh->error;
	$self->{ssh} = $ssh;
	$ssh->system("[ ! -d .doit/lib ] && mkdir -p .doit/lib");
	$ssh->rsync_put({verbose => $debug}, $0, ".doit/"); # XXX verbose?
	$ssh->rsync_put({verbose => $debug}, __FILE__, ".doit/lib/");
	my @cmd = ("perl", "-I.doit", "-I.doit/lib", "-e", q{require "} . File::Basename::basename($0) . q{"; Doit::RPC->new(Doit->init)->run();}, "--", ($dry_run? "--dry-run" : ()));
	if (defined $as) {
	    if ($as eq 'root') {
		unshift @cmd, 'sudo';
	    } else {
		unshift @cmd, 'sudo', '-u', $as;
	    }
	} # XXX add ssh option -t? for password input?
	warn "remote perl cmd: @cmd\n" if $debug;
	my($out, $in, $pid) = $ssh->open2(@cmd);
	$self->{rpc} = Doit::RPC->new(undef, $in, $out);
	$self;
    }

    sub call_remote {
	my($self, @args) = @_;
	$self->{rpc}->call_remote(@args);
    }

    use vars '$AUTOLOAD';
    sub AUTOLOAD {
	(my $method = $AUTOLOAD) =~ s{.*::}{};
	my $self = shift;
	$self->call_remote($method, @_); # XXX or use goto?
    }

    sub DESTROY {
	my $self = shift;
	if ($self->{ssh}) {
	    delete $self->{ssh};
	}
    }
}

1;

__END__
