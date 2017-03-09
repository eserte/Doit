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

# Tests with the Doit repository (if checked out)
SKIP: {
    my $self_git = $d->git_root;
    skip "Not a git checkout", 1 if !$self_git;
    skip "shallow repositories cannot be cloned", 1 if $d->git_is_shallow;

    my $workdir = "$dir/doit";

    run_tests($self_git, $workdir);
}

# Tests with a freshly created git repository
{
    my $workdir = "$dir/newworkdir";
    $d->mkdir($workdir);
    chdir $workdir or die "chdir failed: $!";
    $d->system(qw(git init));
    $d->touch('testfile');
    $d->system(qw(git add testfile));
    local $ENV{GIT_COMMITTER_NAME} = "Some Body";
    local $ENV{GIT_COMMITTER_EMAIL} = 'somebody@example.org';
    local $ENV{GIT_AUTHOR_NAME} = "Some Body";
    local $ENV{GIT_AUTHOR_EMAIL} = 'somebody@example.org';
    $d->system(qw(git commit), '-m', 'test commit');
    $d->change_file('testfile', {add_if_missing => 'some content'});
    $d->system(qw(git add testfile));
    $d->system(qw(git commit), '-m', 'actually some content');

    my $workdir2 = "$dir/newworkdir2";
    run_tests($workdir, $workdir2);
}

chdir "/"; # for File::Temp cleanup

sub run_tests {
    my($repository, $directory) = @_;

    is $d->git_repo_update(repository => $repository, directory => $directory), 1, "first call is a clone of $repository";
    my $commit_hash = $d->git_get_commit_hash(directory => $directory);
    like $commit_hash, qr{^[0-9a-f]{40}$}, 'a sha1';
    ok -d $directory;
    ok -d "$directory/.git";
    is $d->git_repo_update(repository => $repository, directory => $directory), 0, 'second call does nothing';
    is $d->git_get_commit_hash(directory => $directory), $commit_hash, 'unchanged commit hash';

    chdir $directory or die $!;
    $d->system(qw(git reset --hard HEAD^));

    is $d->git_repo_update(repository => $repository, directory => $directory), 1, 'doing a fetch';
    is $d->git_get_commit_hash, $commit_hash, 'again at the old commit hash'; # ... and without specifying $workdir

    $d->mkdir("$dir/exists");
    eval { $d->git_repo_update(repository => $repository, directory => "$dir/exists") };
    like $@, qr{No .git directory found in};

    $d->touch("$dir/file");
    eval { $d->git_repo_update(repository => $repository, directory => "$dir/file") };
    like $@, qr{exists, but is not a directory};
}

__END__
