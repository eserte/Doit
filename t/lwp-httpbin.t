#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use File::Temp qw(tempdir);
use Test::More;

use Doit;
use Doit::Util qw(in_directory);

my($ua_http_tiny, $ua_lwp);

if (eval { require HTTP::Tiny; 1 }) {
    require HTTP::Tiny;
    $ua_http_tiny = HTTP::Tiny->new(timeout => 20);
}
if (eval { require LWP::UserAgent; 1 }) {
    require LWP::UserAgent;
    $ua_lwp = LWP::UserAgent->new;
}

if (!$ua_http_tiny && !$ua_lwp) {
    plan skip_all => 'Neither HTTP::Tiny now LWP::UserAgent installed';
}

#my $httpbin_url = 'https://httpbin.org';
#my $httpbin_url = 'http://eu.httpbin.org';
my $httpbin_url = 'http://httpbingo.org';

if ($ua_http_tiny) {
    my $resp = $ua_http_tiny->get($httpbin_url);
    plan skip_all => "Cannot fetch successfully from $httpbin_url using HTTP::Tiny ($resp->{status} $resp->{reason})" if !$resp->{success};
} elsif ($ua_lwp) {
    my $resp = $ua_lwp->get($httpbin_url);
    plan skip_all => "Cannot fetch successfully from $httpbin_url using LWP::UserAgent (@{[ $resp->status_line ]})" if !$resp->is_success;
} else {
    die "Should not happen";
}

plan 'no_plan';

my $doit = Doit->init;
$doit->add_component('lwp');

my $current_ua;

sub lwp_mirror_wrapper {
    my($url, $text, @more_ua_opts) = @_;
    my @ua_opts = (defined $current_ua ? (ua => $current_ua) : ());
    my $res = eval { $doit->lwp_mirror($url, $text, @ua_opts, @more_ua_opts) };
    if ($@ && (
	       $@ =~ /503 Service Unavailable: Back-end server is at capacity/ ||
	       $@ =~ /599 Internal Exception: Timed out while waiting for socket to become ready for reading/ ||
	       $@ =~ /502 Bad Gateway/ ||
	       $@ =~ /504 Gateway Time-out/
	      )) {
	skip "Unrecoverable backend error ($@), skipping remaining tests", 1;
    }
    ($res, $@);
}

for my $def (
	     [$ua_http_tiny, 'HTTP::Tiny'],
	     [$ua_lwp,       'LWP::UserAgent'],
	    ) {
    my($ua, $ua_name) = @$def;
    next if !$ua;

    if ($ua == $ua_lwp) {
	$current_ua = undef; # use default
    } else {
	$current_ua = $ua;
    }

    my $tmpdir = tempdir("doit-lwp-XXXXXXXX", CLEANUP => 1, TMPDIR => 1);

    in_directory {

    SKIP: {
	    my($res, $err);

	    ($res, $err) = lwp_mirror_wrapper("$httpbin_url/get",   "mirrored.txt");
	    is $res, 1, "$ua_name: mirror was done"
		or diag "lwp_mirror failed with: $err";
	    ($res, $err) = lwp_mirror_wrapper("$httpbin_url/cache", "mirrored.txt");
	    is $res, 0, "$ua_name: no change"
		or diag "lwp_mirror failed with: $err";

	    ($res, $err) = lwp_mirror_wrapper("$httpbin_url/status/500", "mirrored.txt", debug => 1);
	    like $err, qr{ERROR.*mirroring failed: 500 }, "$ua_name: got status 500";

	    ($res, $err) = lwp_mirror_wrapper("unknown_scheme://localhost/foobar", "mirrored.txt", debug => 1);
	    if ($ua == $ua_lwp) {
		like $err, qr{ERROR.*mirroring failed: 400 URL must be absolute}, "$ua_name: got 400 error";
	    } else {
		like $err, qr{ERROR.*mirroring failed: 599 Internal Exception: Unsupported URL scheme 'unknown_scheme}, "$ua_name: got internal exception with extra information";
	    }
	}
    } $tmpdir;
}

__END__
