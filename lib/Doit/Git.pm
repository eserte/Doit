# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2017 Slaven Rezic. All rights reserved.
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
# WWW:  http://www.rezic.de/eserte/
#

package Doit::Git; # Convention: all commands here should be prefixed with 'git_'

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.01';

sub new { bless {}, shift }
sub functions { qw(git_repo_update git_short_status git_root git_get_commit_hash git_get_commit_files git_get_changed_files git_is_shallow git_current_branch) }

sub _in_directory (&$) {
    my($code, $dir) = @_;
    my $save_pwd;
    if (defined $dir) {
	$save_pwd = save_pwd2();
	chdir $dir or die "Can't chdir to $dir: $!";
    }
    $code->();
}

sub git_repo_update {
    my($self, %opts) = @_;
    my $repository = delete $opts{repository};
    my $directory = delete $opts{directory};
    my $origin = delete $opts{origin} || 'origin';
    my $clone_opts = delete $opts{clone_opts};
    die "Unhandled options: " . join(" ", %opts) if %opts;

    my $save_pwd = save_pwd2();

    my $has_changes = 0;
    if (-e $directory) {
	if (!-d $directory) {
	    die "'$directory' exists, but is not a directory\n";
	}
	chdir $directory
	    or die "Can't chdir $directory: $!";
	if (!-d ".git") {
	    die "No .git directory found in '$directory', refusing to clone...\n";
	}
	chomp(my $actual_repository = `git config --get 'remote.$origin.url'`); # XXX should use something "safe"
	if ($actual_repository ne $repository) {
	    die "remote $origin does not point to $repository, but to $actual_repository\n";
	}
	$self->system(qw(git fetch));
	my $status = $self->git_short_status;
	if ($status eq '>') {
	    $self->system(qw(git pull)); # XXX actually would be more efficient to do a merge or rebase, but need to figure out how git does it exactly...
	    $has_changes = 1;
	} # else: ahead, diverged, or something else
    } else {
	my @cmd = (qw(git clone --origin), $origin);
	if ($clone_opts) {
	    push @cmd, @$clone_opts;
	}
	push @cmd, $repository, $directory;
	$self->system(@cmd);
	$has_changes = 1;
    }
    $has_changes;
}

sub git_short_status {
    my($self, %opts) = @_;
    my $directory = delete $opts{directory};
    die "Unhandled options: " . join(" ", %opts) if %opts;

    my $untracked_files = 'normal'; # XXX or "no"? make it configurable?

    _in_directory {
	local $ENV{LC_ALL} = 'C';

	{
	    my @cmd = ("git", "status", "--untracked-files=$untracked_files", "--porcelain");
	    open my $fh, "-|", @cmd
		or die "Can't run '@cmd': $!";
	    my $has_untracked;
	    my $has_uncommitted;
	    while (<$fh>) {
		if (m{^\?\?}) {
		    $has_untracked++;
		} else {
		    $has_uncommitted++;
		}
		# Shortcut, exit as early as possible
		if ($has_uncommitted) {
		    if ($has_untracked) {
			return '<<*';
		    } elsif ($untracked_files eq 'no') {
			return '<<';
		    } # else we have to check further, for possible untracked files
		}
	    }
	    if ($has_uncommitted) {
		return '<<';
	    } elsif ($has_untracked) {
		return '*';
	    }
	}

	{
	    my @cmd = ("git", "status", "--untracked-files=no");
	    open my $fh, "-|", @cmd
		or die "Can't run '@cmd': $!";
	    my $l;
	    $l = <$fh>;
	    $l = <$fh>;
	    if      ($l =~ m{^(# )?Your branch is ahead}) {
		return '<';
	    } elsif ($l =~ m{^(# )?Your branch is behind}) {
		return '>';
	    } elsif ($l =~ m{^(# )?Your branch and .* have diverged}) {
		return '<>';
	    }
	}

	if (-f ".git/svn/.metadata") {
	    # simple-minded heuristics, works only with svn standard branch
	    # layout
	    my $root_dir = $self->git_root;
	    if (open my $fh_remote, "$root_dir/.git/refs/remotes/trunk") {
		if (open my $fh_local, "$root_dir/.git/refs/heads/master") {
		    chomp(my $sha1_remote = <$fh_remote>);
		    chomp(my $sha1_local = <$fh_local>);
		    if ($sha1_remote ne $sha1_local) {
			my $remote_is_newer;
			if (open my $log_fh, '-|', 'git', 'log', '--pretty=format:%H', 'master..remotes/trunk') {
			    if (scalar <$log_fh>) {
				$remote_is_newer = 1;
			    }
			}
			my $local_is_newer;
			if (open my $log_fh, '-|', 'git', 'log', '--pretty=format:%H', 'remotes/trunk..master') {
			    if (scalar <$log_fh>) {
				$local_is_newer = 1;
			    }
			}
			if ($remote_is_newer && $local_is_newer) {
			    return '<>';
			} elsif ($remote_is_newer) {
			    return '>';
			} elsif ($local_is_newer) {
			    return '<';
			} else {
			    return '?'; # Should never happen
			}
		    }
		}
	    }
	}

	return '';

    } $directory;
}

sub git_root {
    my($self, %opts) = @_;
    my $directory = delete $opts{directory};
    die "Unhandled options: " . join(" ", %opts) if %opts;

    _in_directory {
	chomp(my $dir = `git rev-parse --show-toplevel`);
	$dir;
    } $directory;
}

sub git_get_commit_hash {
    my($self, %opts) = @_;
    my $directory = delete $opts{directory};
    die "Unhandled options: " . join(" ", %opts) if %opts;

    _in_directory {
	chomp(my $commit = `git log -1 --format=%H`);
	$commit;
    } $directory;
}

sub git_get_commit_files {
    my($self, %opts) = @_;
    my $directory = delete $opts{directory};
    my $commit    = delete $opts{commit}; if (!defined $commit) { $commit = 'HEAD' }
    die "Unhandled options: " . join(" ", %opts) if %opts;

    my @files;
    _in_directory {
	my @cmd = ('git', 'show', $commit, '--pretty=format:', '--name-only');
	open my $fh, '-|', @cmd
	    or die "Error running @cmd: $!";
	my $first = <$fh>;
	if ($first ne "\n") { # first line is empty for older git versions (e.g. 1.7.x)
	    chomp $first;
	    push @files, $first;
	}
	while(<$fh>) {
	    chomp;
	    push @files, $_;
	}
	close $fh
	    or die "Error while running @cmd: $!";
    } $directory;
    @files;
}

sub git_get_changed_files {
    my($self, %opts) = @_;
    my $directory = delete $opts{directory};
    my @files;
    _in_directory {
	my @cmd = qw(git status --porcelain);
	open my $fh, '-|', @cmd
	    or die "Error running @cmd: $!";
	while(<$fh>) {
	    chomp;
	    s{^...}{};
	    push @files, $_;
	}
	close $fh
	    or die "Error while running @cmd: $!";
    } $directory;
    @files;
}

sub git_is_shallow {
    my($self, %opts) = @_;
    my $directory = delete $opts{directory};
    die "Unhandled options: " . join(" ", %opts) if %opts;

    my $git_root = $self->git_root(directory => $directory);
    -f "$git_root/.git/shallow" ? 1 : 0;
}

sub git_current_branch {
    my($self, %opts) = @_;
    my $directory = delete $opts{directory};
    die "Unhandled options: " . join(" ", %opts) if %opts;

    _in_directory {
	my $git_root = $self->git_root;
	my $fh;
	open $fh, "<", "$git_root/.git/HEAD" and $_ = <$fh> and m{refs/heads/(\S+)} and return $1;
	undef;
    } $directory;
}

# REPO BEGIN
# REPO NAME save_pwd2 /Users/eserte/src/srezic-repository 
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

1;

__END__
