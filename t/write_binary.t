#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use File::Temp qw(tempdir);
use Test::More;

BEGIN {
    plan skip_all => 'No Capture::Tiny available' if !eval { require Capture::Tiny; Capture::Tiny->import('capture'); 1 };
    plan skip_all => 'No Term::ANSIColor available' if !eval { require Term::ANSIColor; Term::ANSIColor->import('colorstrip'); 1 };
}
plan 'no_plan';

use Doit;
use Doit::Extcmd qw(is_in_path);

sub slurp ($) { open my $fh, shift or die $!; local $/; <$fh> }

my $d = Doit->init;

my $dir = tempdir(CLEANUP => 1);

{
    my($stdout, $stderr) = capture {
	$d->write_binary("$dir/test", "testcontent\n");
    };
    is $stdout, '';
    like colorstrip($stderr), qr{^INFO: Create new file .*test with content:\ntestcontent\n$}, 'create file info';
    is slurp("$dir/test"), "testcontent\n";
}

{
    my($stdout, $stderr) = capture {
	$d->write_binary("$dir/test", "testcontent\n");
    };
    is $stdout, '';
    is colorstrip($stderr), '', 'nothing happens';
    is slurp("$dir/test"), "testcontent\n";
}

{
    my($stdout, $stderr) = capture {
	$d->write_binary("$dir/test", "new testcontent\n");
    };
    is $stdout, '';
    if (is_in_path 'diff') {
	like colorstrip($stderr), qr{^INFO: Replace existing file .*test with diff}, 'replace + diff';
    } else {
	like colorstrip($stderr), qr{^INFO:.*diff not available};
    }
    is slurp("$dir/test"), "new testcontent\n";
}

{
    my($stdout, $stderr) = capture {
	$d->write_binary({quiet=>1}, "$dir/test2", "testcontent\n");
    };
    is $stdout, '';
    like colorstrip($stderr), qr{^INFO: Create new file .*test2$}, 'create new file in quiet=1 mode';
    is slurp("$dir/test2"), "testcontent\n";
}

{
    my($stdout, $stderr) = capture {
	$d->write_binary({quiet=>1}, "$dir/test", "new2 testcontent\n");
    };
    is $stdout, '';
    like colorstrip($stderr), qr{^INFO: Replace existing file .*test$}, 'replace file in quiet=1 mode';
    is slurp("$dir/test"), "new2 testcontent\n";
}

{
    my($stdout, $stderr) = capture {
	$d->write_binary({quiet=>2}, "$dir/test2", "testcontent\n");
    };
    is $stdout, '';
    is $stderr, '', 'insert completely quiet';
    is slurp("$dir/test2"), "testcontent\n";
}

{
    my($stdout, $stderr) = capture {
	$d->write_binary({quiet=>2}, "$dir/test2", "new testcontent\n");
    };
    is $stdout, '';
    is $stderr, '', 'replace completely quiet';
    is slurp("$dir/test2"), "new testcontent\n";
}

__END__
