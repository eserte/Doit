#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use File::Temp 'tempdir';
use Test::More 'no_plan';

use Doit;

sub slurp ($) { open my $fh, shift or die $!; local $/; <$fh> }

my $tempdir = tempdir('doit_XXXXXXXX', TMPDIR => 1, CLEANUP => 1);
chdir $tempdir or die "Can't chdir to $tempdir: $!";

my $r = Doit->init;

eval { $r->change_file("blubber") };
like $@, qr{blubber does not exist};

eval { $r->change_file(".") };
like $@, qr{\. is not a file};

$r->touch("work-file");
$r->chmod(0600, "work-file");
$r->change_file("work-file");
ok -z "work-file", "still empty";

for my $iter (1..2) {
    $r->change_file("work-file",
		    {add_if_missing => "a new line"},
		   );
    is slurp("work-file"), "a new line\n", ($iter == 1 ? "first iteration: add new line" : "second iteration: do nothing");
}

$r->change_file("work-file",
		{add_if_missing => "another new line"});
is slurp("work-file"), "a new line\nanother new line\n";

$r->change_file("work-file",
		{add_if_missing => "add_after test",
		 add_after => qr{^a new line},
		});
is slurp("work-file"), "a new line\nadd_after test\nanother new line\n";

eval { $r->change_file("work-file",
		       {add_if_missing => "second add_after test",
			add_after => qr{^non-existent file},
		       }) };
like $@, qr{Cannot find .* in file};		       

$r->change_file("work-file",
		{match => qr{^add_after test},
		 replace => "replace test"});
is slurp("work-file"), "a new line\nreplace test\nanother new line\n";

$r->change_file("work-file",
		{match => qr{^replace test},
		 action => sub { $_[0] .= " adding something" }});
is slurp("work-file"), "a new line\nreplace test adding something\nanother new line\n";

$r->change_file("work-file",
		{unless_match => qr{^unless match -- this will not match},
		 action => sub { unshift @{$_[0]}, "add something on top" }});
is slurp("work-file"), "add something on top\na new line\nreplace test adding something\nanother new line\n";

eval { $r->change_file("work-file",
		       {match => "this is not a Regexp",
			action => sub { "dummy" }}) };
like $@, qr{match must be a regexp};

eval { $r->change_file("work-file",
		       {match => qr{^dummy match}}) };
like $@, qr{action or replace is missing};

eval { $r->change_file("work-file",
		       {match => qr{^dummy match},
			action => "this is not CODE"}) };
like $@, qr{action must be a sub reference};

eval { $r->change_file("work-file",
		       {unless_match => qr{^unless match -- this will not match}}) };
like $@, qr{action is missing};

eval { $r->change_file("work-file",
		       {unless_match => qr{^unless match -- this will not match},
			action => "this is not CODE",
		       }) };
like $@, qr{action must be a sub reference};

eval { $r->change_file("work-file",
		       {}) };
like $@, qr{match or unless_match is missing};

{
    my @s = stat("work-file");
    is $s[2]&07777, 0600, 'preserved mode';
}
__END__
