#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use Doit;

use File::Temp ();
use Test::More;

plan skip_all => 'No suitable ini module available'
    if !eval { require Config::IOD::INI; 1 };
plan 'no_plan';

sub slurp ($) { open my $fh, shift or die $!; local $/; <$fh> }

my $doit = Doit->init;
$doit->add_component('ini');

{
    my $orig_ini = <<'EOF';
; comment 1
[connection]
id=public
type=wifi
permissions=

; comment 2

; comment 3

[wifi]
mac-address-blacklist=
mode=infrastructure
ssid=ssid

[wifi-security]
auth-alg=open
key-mgmt=wpa-psk
psk=secret
EOF

    my $tmp = File::Temp->new;
    $tmp->print($orig_ini);
    $tmp->close;

    $doit->ini_set_implementation('Config::IOD::INI');
    ok $doit->ini_change("$tmp", "wifi-security.psk" => "new-secret", "connection.id" => "non-public"), 'changes detected';
    {
	my $new_ini = slurp("$tmp");
	like $new_ini, qr{psk=new-secret}, 'found 1st changed value';
	like $new_ini, qr{id=non-public}, 'found 2nd changed value';
    }

    ok $doit->ini_change("$tmp", sub {
			     my($self) = @_;
			     my $confobj = $self->confobj;
			     isa_ok $confobj, 'Config::IOD::Document';
			     # undo the changes done above
			     $confobj->set_value('wifi-security', 'psk', 'secret');
			     $confobj->set_value('connection', 'id', 'public');
			 }), 'changes detected';

    ok !$doit->ini_change("$tmp", "wifi-security.psk" => "secret"), 'no changes detected';
    {
	my $new_ini = slurp("$tmp");
	is $new_ini, $orig_ini, 'all changes in ini file were reverted';
    }
}
