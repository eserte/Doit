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
    package X;
    sub new {
	my $class = shift;
	my $self = bless { }, $class;
	# XXX hmmm, creating now self-refential data structures ...
	$self->{runner}    = XRunner->new($self);
	$self->{dryrunner} = XRunner->new($self, 1);
	$self;
    }
    sub runner    { shift->{runner} }
    sub dryrunner { shift->{dryrunner} }

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
	XCommands->new(@commands);
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
	
	XCommands->new(@commands);
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
	    XCommands->new();
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
	XCommands->new(@commands);
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
	XCommands->new(@commands);
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
	XCommands->new(@commands);
    }

    sub cmd_rename {
	my($self, $from, $to) = @_;
	my @commands;
	push @commands, {
			 code => sub { rename $from, $to or die $! },
			 msg  => "rename $from, $to",
			};
	XCommands->new(@commands);
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
	XCommands->new(@commands);
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
	XCommands->new(@commands);
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
	XCommands->new(@commands);
    }

    sub cmd_system {
	my($self, @args) = @_;
	my @commands;
	push @commands, {
			 code => sub { system @args; die if $? != 0; },
			 msg  => "@args",
			};
	XCommands->new(@commands);
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
	XCommands->new(@commands);
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
	XCommands->new(@commands);
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
	XCommands->new(@commands);
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
	XCommands->new(@commands);  
    }
}

{
    package XCommands;
    sub new {
	my($class, @commands) = @_;
	my $self = bless \@commands, $class;
	$self;
    }
    sub commands { @{$_[0]} }
    sub doit {
	my($self) = @_;
	for my $command ($self->commands) {
	    print STDERR "INFO: " . $command->{msg} . "\n";
	    $command->{code}->();
	}
    }
    sub show {
	my($self) = @_;
	for my $command ($self->commands) {
	    print STDERR "INFO: " . $command->{msg} . " (dry-run)\n";
	}
    }
}

{
    package XRunner;
    sub new {
	my($class, $X, $dryrun) = @_;
	bless { X => $X, dryrun => $dryrun }, $class;
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
		 qw(run), # IPC::Run
		 qw(cond_run), # conditional run
		 qw(touch), # like unix touch
		 qw(write_binary), # like File::Slurper
		) {
	install_cmd $cmd;
    }
}

{
    package main;
    use Test::More 'no_plan';
    use Getopt::Long;
    GetOptions("dry-run|n" => \my $dry_run) or die "usage?";
    my $r = ($dry_run ? X->new->dryrunner : X->new->runner);
    $r->touch("/tmp/decl-test");
    ok -f "/tmp/decl-test";
    $r->touch("/tmp/decl-test");
    ok -f "/tmp/decl-test";
    $r->utime(undef, undef, "/tmp/decl-test");
    { my @s = stat "/tmp/decl-test"; cmp_ok $s[9], ">", 0 }
    $r->chmod(0755, "/tmp/decl-test");
    $r->chmod(0755, "/tmp/decl-test");
    $r->chmod(0644, "/tmp/decl-test");
    $r->chmod(0644, "/tmp/decl-test");
    $r->chown($>, undef, "/tmp/decl-test");
    $r->chown($>, undef, "/tmp/decl-test");
    $r->chown(undef, (split / /, $))[1], "/tmp/decl-test");
    $r->chown(undef, (split / /, $))[1], "/tmp/decl-test");
    $r->rename("/tmp/decl-test", "/tmp/decl-test2");
    $r->rename("/tmp/decl-test2", "/tmp/decl-test");
    $r->symlink("tmp/decl-test", "/tmp/decl-test-symlink");
    ok -l "/tmp/decl-test-symlink";
    $r->symlink("tmp/decl-test", "/tmp/decl-test-symlink");
    $r->unlink("/tmp/decl-test-symlink");
    ok ! -e "/tmp/decl-test-symlink";
    $r->write_binary("/tmp/decl-test", "some content\n");
    $r->write_binary("/tmp/decl-test", "some content\n");
    $r->write_binary("/tmp/decl-test", "different content\n");
    $r->write_binary("/tmp/decl-test", "different content\n");
    $r->unlink("/tmp/decl-test");
    ok ! -f "/tmp/decl-test";
    ok ! -e "/tmp/decl-test";
    $r->unlink("/tmp/decl-test");
    $r->mkdir("/tmp/decl-test");
    ok -d "/tmp/decl-test";
    $r->mkdir("/tmp/decl-test");
    ok -d "/tmp/decl-test";
    $r->make_path("/tmp/decl-test", "/tmp/decl-deep/test");
    ok -d "/tmp/decl-deep/test";
    $r->make_path("/tmp/decl-test", "/tmp/decl-deep/test");
    $r->rmdir("/tmp/decl-test");
    ok ! -d "/tmp/decl-test";
    ok ! -e "/tmp/decl-test";
    $r->rmdir("/tmp/decl-test");
    $r->remove_tree("/tmp/decl-test", "/tmp/decl-deep/test");
    ok ! -d "/tmp/decl-deep/test";
    $r->remove_tree("/tmp/decl-test", "/tmp/decl-deep/test");
    $r->system("date");
    $r->run(["date"]);
    $r->system("hostname", "-f");
    $r->run(["hostname", "-f"]);
    $r->cond_run(cmd => [qw(echo unconditional cond_run)]);
    $r->cond_run(if => sub { rand(1) < 0.5 }, cmd => [qw(echo yes)]);
}

__END__
