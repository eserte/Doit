#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use File::Temp qw(tempdir);
use Test::More;

use Doit;
use Doit::Extcmd qw(is_in_path);

if (!is_in_path('git')) {
    plan skip_all => 'git not in PATH';
}

plan 'no_plan';

my $d = Doit->init;
$d->add_component('git');

my $dir = tempdir('doit-git-XXXXXXXX', CLEANUP => 1, TMPDIR => 1);

SKIP: {
    my $self_git = $d->git_root;
    skip "Not a git checkout", 1 if !$self_git;
    skip "shallow repositories cannot be cloned", 1 if $d->git_is_shallow;

    my $workdir = "$dir/doit";

    is $d->git_repo_update(repository => $self_git, directory => $workdir), 1, 'first call is a clone';
    my $commit_hash = $d->git_get_commit_hash(directory => $workdir);
    like $commit_hash, qr{^[0-9a-f]{40}$}, 'a sha1';
    ok -d $workdir;
    ok -d "$workdir/.git";
    ok -f "$workdir/lib/Doit.pm";
    is $d->git_repo_update(repository => $self_git, directory => $workdir), 0, 'second call does nothing';
    is $d->git_get_commit_hash(directory => $workdir), $commit_hash, 'unchanged commit hash';

    chdir $workdir or die $!;
    $d->system(qw(git reset --hard HEAD^));

    is $d->git_repo_update(repository => $self_git, directory => $workdir), 1, 'doing a fetch';
    is $d->git_get_commit_hash, $commit_hash, 'again at the old commit hash'; # ... and without specifying $workdir

    chdir "/"; # for File::Temp cleanup

    $d->mkdir("$dir/exists");
    eval { $d->git_repo_update(repository => $self_git, directory => "$dir/exists") };
    like $@, qr{No .git directory found in};

    $d->touch("$dir/file");
    eval { $d->git_repo_update(repository => $self_git, directory => "$dir/file") };
    like $@, qr{exists, but is not a directory};
}

__END__
