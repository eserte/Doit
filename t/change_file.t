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

my $changes;

eval { $r->change_file() };
like $@, qr{ERROR.*\QExpecting at least a filename and one or more changes}, 'error: too less arguments';

eval { $r->change_file({unhandled_option=>1}, "blubber") };
like $@, qr{ERROR.*\QUnhandled options: unhandled_option }, 'error: unhandled option';

eval { $r->change_file("blubber") };
like $@, qr{blubber does not exist};

eval { $r->change_file(".") };
like $@, qr{\. is not a file};

$r->touch("work-file");
$r->chmod(0600, "work-file");
my $got_mode = (stat("work-file"))[2] & 07777;
if ($^O ne 'MSWin32') { # here it's 0666
    is $got_mode, 0600, 'chmod worked';
}
$changes = $r->change_file("work-file");
ok -z "work-file", "still empty";
ok !$changes, 'no changes';
is $changes, 0, 'no changes == zero changes';

for my $iter (1..2) {
    $changes = $r->change_file("work-file",
			       {add_if_missing => "a new line"},
			      );
    is slurp("work-file"), "a new line\n", ($iter == 1 ? "first iteration: add new line" : "second iteration: do nothing");
    is $changes, $iter==1 ? 1 : 0;
}

$changes = $r->change_file("work-file",
			   {add_if_missing => "another new line"});
is slurp("work-file"), "a new line\nanother new line\n";
is $changes, 1;

$changes = $r->change_file("work-file",
			   {add_if_missing => "add_after test",
			    add_after => qr{^a new line},
			   });
is slurp("work-file"), "a new line\nadd_after test\nanother new line\n";
is $changes, 1;

eval { $r->change_file("work-file",
		       {add_if_missing => "second add_after test",
			add_after => qr{^non-existent file},
		       }) };
like $@, qr{Cannot find .* in file};

$r->change_file("work-file",
		{match => qr{^add_after test},
		 replace => "replace test 1"});
is slurp("work-file"), "a new line\nreplace test 1\nanother new line\n", 'match with regexp';

$r->change_file("work-file",
		{match => 'replace test 1',
		 replace => "replace test"});
is slurp("work-file"), "a new line\nreplace test\nanother new line\n", 'match with string';

$r->change_file("work-file",
		{match => "this will not match",
		 replace => 'this should never be added'});
is slurp("work-file"), "a new line\nreplace test\nanother new line\n";

$r->change_file("work-file",
		{match => qr{^another new line},
		 replace => ""});
is slurp("work-file"), "a new line\nreplace test\n\n", 'replace with empty string generated empty line';

$r->change_file("work-file",
		{match => qr{^$}, replace => "another new line"});
is slurp("work-file"), "a new line\nreplace test\nanother new line\n";

$r->change_file("work-file",
		{match => qr{^replace test},
		 action => sub { $_[0] .= " adding something" }});
is slurp("work-file"), "a new line\nreplace test adding something\nanother new line\n";

$r->change_file("work-file",
		{unless_match => qr{^unless match -- this will not match},
		 action => sub { unshift @{$_[0]}, "add something on top" }});
is slurp("work-file"), "add something on top\na new line\nreplace test adding something\nanother new line\n";

$changes = $r->change_file("work-file",
			   {add_if_missing => "add first line of two"},
			   {add_if_missing => "add second line of two"},
		          );
is $changes, 2, 'two changes';

$changes = $r->change_file({
			    check => sub {
				my $file = shift;
				$r->system($^X, '-nle', 'END { if ($. == 7) { exit 0 } else { die "Expected seven lines in work-file, got $." } }', $file);
				1;
			    },
			   },
			   "work-file",
			   {add_if_missing => "add another line"},
			  );
is $changes, 1, 'one change, with check';

{ # add_after vs. add_after_first vs. add_before vs. add_before_last
    $r->touch('work-file-2');
    $r->chmod(0600, 'work-file-2');

    for my $iter (1..2) {
	$changes = $r->change_file('work-file-2',
				   {add_if_missing => 'a new line'},
				   {add_if_missing => 'a new line 2'},
				   {add_if_missing => 'this is the last line'},
				  );
	is $changes, ($iter==1 ? 3 : 0), "changes in iteration $iter";
	is slurp('work-file-2'), "a new line\na new line 2\nthis is the last line\n";
    }

    for my $iter (1..2) {
	$changes = $r->change_file('work-file-2',
				   {add_if_missing => 'middle line',
				    add_after => qr{^a new line},
				   });
	is $changes, ($iter==1 ? 1 : 0), "changes in iteration $iter";
	is slurp('work-file-2'), "a new line\na new line 2\nmiddle line\nthis is the last line\n";
    }

    for my $iter (1..2) {
	$changes = $r->change_file('work-file-2',
				   {add_if_missing => 'the add_after_first test',
				    add_after_first => qr{^a new line},
				   });
	is $changes, ($iter==1 ? 1 : 0), "changes in iteration $iter";
	is slurp('work-file-2'), "a new line\nthe add_after_first test\na new line 2\nmiddle line\nthis is the last line\n";
    }

    for my $iter (1..2) {
	$changes = $r->change_file('work-file-2',
				   {add_if_missing => 'the add_before test',
				    add_before => qr{^a new line},
				   });
	is $changes, ($iter==1 ? 1 : 0), "changes in iteration $iter";
	is slurp('work-file-2'), "the add_before test\na new line\nthe add_after_first test\na new line 2\nmiddle line\nthis is the last line\n";
    }

    for my $iter (1..2) {
	$changes = $r->change_file('work-file-2',
				   {add_if_missing => 'the add_before_last test',
				    add_before_last => qr{^a new line},
				   });
	is $changes, ($iter==1 ? 1 : 0), "changes in iteration $iter";
	is slurp('work-file-2'), "the add_before test\na new line\nthe add_after_first test\nthe add_before_last test\na new line 2\nmiddle line\nthis is the last line\n";
    }
}

######################################################################
# Error checks
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

eval { $r->change_file({
			check => sub {
			    die "Simulate failed check";
			},
		       },
		       "work-file",
		       {add_if_missing => "add another line for the fail-check simulation"},
		      ) };
like $@, qr{Simulate failed check};

{
    my @s = stat("work-file");
    is $s[2]&07777, $got_mode, 'preserved mode';
}
__END__
