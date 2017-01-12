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
    package main;
    use Decl;
    use Test::More 'no_plan';
    use Getopt::Long;
    GetOptions("dry-run|n" => \my $dry_run) or die "usage?";
    my $x = X->new;
    my $r = ($dry_run ? $x->dryrunner : $x->runner);
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
    $r->cond_run(if => sub { 1 }, cmd => [qw(echo always true)]);
    $r->cond_run(if => sub { 0 }, cmd => [qw(echo), 'never true, should never happen!!!']);
    $r->cond_run(if => sub { rand(1) < 0.5 }, cmd => [qw(echo yes)]);

    $r->install_generic_cmd('never_executed', sub { 0 }, sub { die "never executed" });
    $r->never_executed();
    $r->install_generic_cmd('mytest', sub {
				my($self, $args) = @_;
				@$args;
			    }, sub {
				my($self, $args) = @_;
				warn "args is @$args";
			    });
    $r->mytest(1);
    $r->mytest(0);
}

__END__
