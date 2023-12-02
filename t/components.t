#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;

use File::Temp qw(tempdir);
use Test::More;

use Doit;

sub check_component_function {
    my($d, $function) = @_;
    !!$d->can($function);
}

sub slurp ($) { open my $fh, shift or die $!; local $/; <$fh> }

return 1 if caller;

require FindBin;
{ no warnings 'once'; push @INC, $FindBin::RealBin; }
require TestUtil;

plan 'no_plan';

my $doit = Doit->init;
$doit->add_component('git');
pass 'add_component called with short component name';
$doit->add_component('Doit::Deb');
pass 'add_component called with module name';
eval { $doit->add_component('Doit::ThisComponentDoesNotExist') };
like $@, qr{ERROR:.* Cannot load Doit::ThisComponentDoesNotExist}, 'non-existing component';

ok $doit->call_with_runner('check_component_function', 'deb_missing_packages'), 'available deb component locally';
ok $doit->call_with_runner('check_component_function', 'git_repo_update'),      'available git component locally';

# XXX $doit->{components} is an internal member!
is_deeply [map { $_->{module} } @{ $doit->{components} }], ['Doit::Git', 'Doit::Deb'], 'two components loaded';
$doit->add_component('git');
$doit->add_component('deb');
is_deeply [map { $_->{module} } @{ $doit->{components} }], ['Doit::Git', 'Doit::Deb'], 'still two components loaded';

SKIP: {
    my $number_of_tests = 2;

    my %info;
    my $sudo = TestUtil::get_sudo($doit, info => \%info);
    if (!$sudo) {
	skip $info{error}, $number_of_tests;
    }

    ok $sudo->call_with_runner('check_component_function', 'deb_missing_packages'),   'available deb component through sudo';
    ok $sudo->call_with_runner('check_component_function', 'git_repo_update'),        'available git component through sudo';
}

{
    my $testcomponent_code = <<'EOF';
package
    Doit::Testcomponent;
use strict;
use warnings;
sub new { bless {}, shift }
sub functions { qw(testcomponent_function) }
sub add_components { qw(file) }
sub testcomponent_function {
    my($doit, $destfile) = @_;
    $doit->file_atomic_write($destfile, sub {
	 my $fh = shift;
	 print $fh "Hello, world!\n";
    });
}
1;
EOF
    local @INC = (sub { return if $_[1] ne 'Doit/Testcomponent.pm'; \$testcomponent_code }, @INC);
    my $doit = Doit->init;
    $doit->add_component('testcomponent');
    ok $doit->call_with_runner('check_component_function', 'testcomponent_function'), 'available testcomponent locally';
    ok $doit->call_with_runner('check_component_function', 'file_atomic_write'),      'adding another component within a component works locally';
    my $tempdir = tempdir("doit_XXXXXXXX", TMPDIR =>1, CLEANUP => 1);
    my $tempfile = "$tempdir/test";
    $doit->testcomponent_function($tempfile);
    is slurp($tempfile), "Hello, world!\n", 'expected outcome of component function';
}

__END__
