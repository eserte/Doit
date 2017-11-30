#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use Cwd qw(realpath getcwd);
use File::Temp qw(tempdir);
use Test::More;

use Doit;
use Doit::Extcmd qw(is_in_path);
use Doit::Util qw(in_directory);

if (!is_in_path('git')) {
    plan skip_all => 'git not in PATH';
}

plan 'no_plan';

my $d = Doit->init;
$d->add_component('git');

# realpath() needed on darwin
my $dir = realpath(tempdir('doit-git-XXXXXXXX', CLEANUP => 1, TMPDIR => 1));

# A private git-short-status script; should behave the same.
my $my_git_short_status;
if (-x "$ENV{HOME}/bin/sh/git-short-status") {
    $my_git_short_status = "$ENV{HOME}/bin/sh/git-short-status";
}

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

    # after init checks
    is $d->git_root, $workdir, 'git_root in root directory';
    is_deeply [$d->git_get_changed_files], [], 'no changed files in fresh empty directory';
    git_short_status_check($d, '', 'empty directory, not dirty');
    is $d->git_current_branch, 'master';

    # dirty
    $d->touch('testfile');
    is_deeply [$d->git_get_changed_files], ['testfile'], 'new file detected';
    git_short_status_check($d, '*', 'untracked file detected');

    # git-add
    $d->system(qw(git add testfile));
    git_short_status_check($d, '<<', 'uncommitted file detected');

    # git-commit
    _git_commit_with_author('test commit');
    is_deeply [$d->git_get_changed_files], [], 'no changed files after commit';
    is_deeply [$d->git_get_commit_files], ['testfile'], 'git_get_commit_files';
    is_deeply [$d->git_get_commit_files(commit => 'HEAD')], ['testfile'], 'git_get_commit_files with explicit commit';
    git_short_status_check($d, '', "there's no upstream, so no '<'");

    $d->change_file('testfile', {add_if_missing => 'some content'});
    git_short_status_check($d, '<<', 'dirty after change');

    $d->system(qw(git add testfile));
    _git_commit_with_author('actually some content');
    git_short_status_check($d, '', 'freshly committed');

    my $workdir2 = "$dir/newworkdir2";
    run_tests($workdir, $workdir2);

    $d->mkdir('subdir');
    in_directory {
	is $d->git_root, $workdir, 'git_root in subdirectory';
    } 'subdir';

    Doit::Util::in_directory(sub {
	is $d->git_root, $workdir, 'in_directory call without prototype';
    }, 'subdir');

    is $d->git_config(key => "test.key"), undef, 'config key does not exist yet';
    $d->git_config(key => "test.key", val => "test.val");
    is $d->git_config(key => "test.key"), "test.val", 'config key now exists';
    $d->git_config(key => "test.key", val => "test.val2");
    is $d->git_config(key => "test.key"), "test.val2", 'config key now changed';
    $d->git_config(key => "test.key", val => "test.val2");
    is $d->git_config(key => "test.key"), "test.val2", 'nothing changed now';
    $d->git_config(key => "test.key", unset => 1);
    is $d->git_config(key => "test.key"), undef, 'config key was removed';
    $d->git_config(key => "test.key", unset => 1);
    is $d->git_config(key => "test.key"), undef, 'config key is still removed';

    is $d->git_repo_update(
			   repository => "$workdir/.git",
			   repository_aliases => [$workdir],
			   directory => $workdir2,
			  ), 0, "handling repository_aliases";

    $d->mkdir("$dir/empty_exists");
    $d->git_repo_update(repository => "$workdir/.git", directory => "$dir/empty_exists");
    ok -d "$dir/empty_exists/.git";
}

chdir "/"; # for File::Temp cleanup

sub run_tests {
    my($repository, $directory) = @_;

    is $d->git_repo_update(repository => $repository, directory => $directory), 1, "first call is a clone of $repository";
    git_short_status_check({directory => $directory}, $d, '', 'not dirty after clone');
    my $commit_hash = $d->git_get_commit_hash(directory => $directory);
    like $commit_hash, qr{^[0-9a-f]{40}$}, 'a sha1';
    ok -d $directory;
    ok -d "$directory/.git";
    is $d->git_repo_update(repository => $repository, directory => $directory), 0, 'second call does nothing';
    is $d->git_get_commit_hash(directory => $directory), $commit_hash, 'unchanged commit hash';
    is $d->git_repo_update(repository => $repository, directory => $directory, quiet => 1), 0, 'third call is quiet';

    in_directory {
	$d->system(qw(git reset --hard HEAD^));
	git_short_status_check($d, '>', 'remote is now newer');

	is $d->git_repo_update(repository => $repository, directory => $directory), 1, 'doing a fetch';
	is $d->git_get_commit_hash, $commit_hash, 'again at the old commit hash'; # ... and without specifying $workdir
	git_short_status_check($d, '', 'freshly fetched');

	$d->touch('new_file');
	git_short_status_check($d, '*', 'file was touched');
	$d->system(qw(git add new_file));
	_git_commit_with_author('test commit in clone');
	git_short_status_check($d, '<', 'ahead of origin');

	$d->system(qw(git checkout -b new_branch));
	is $d->git_current_branch, 'new_branch';
    } $directory;

    $d->mkdir("$dir/exists");
    $d->create_file_if_nonexisting("$dir/exists/make_directory_non_empty");
    eval { $d->git_repo_update(repository => $repository, directory => "$dir/exists") };
    like $@, qr{ERROR.*No .git directory found in};

    $d->touch("$dir/file");
    eval { $d->git_repo_update(repository => $repository, directory => "$dir/file") };
    like $@, qr{ERROR.*exists, but is not a directory};
}

sub _git_commit_with_author {
    my $msg = shift;
    local $ENV{GIT_COMMITTER_NAME} = "Some Body";
    local $ENV{GIT_COMMITTER_EMAIL} = 'somebody@example.org';
    local $ENV{GIT_AUTHOR_NAME} = "Some Body";
    local $ENV{GIT_AUTHOR_EMAIL} = 'somebody@example.org';
    $d->system(qw(git commit), '-m', $msg);
}

sub git_short_status_check {
    my %options;
    if (ref $_[0] eq 'HASH') {
	%options = %{ shift @_ };
    }
    my($doit, $expected, $testname) = @_;
    my $doit_result = $doit->git_short_status(%options);
    is $doit_result, $expected, $testname;
    if ($my_git_short_status) {
	my $directory = $options{directory} ? $options{directory} : getcwd;
	in_directory {
	    chomp(my $script_result = $doit->info_qx({quiet=>1}, $my_git_short_status, '-with-untracked'));
	    is $script_result, $doit_result, "$testname (against $my_git_short_status)";
	} $directory;
    }
}

__END__
