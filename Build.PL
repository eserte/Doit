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
use FindBin;
use lib "$FindBin::RealBin/lib";

use Config;
use Digest::MD5 qw(md5_hex);
use File::Basename;
use Doit;
use Doit::Log;

my $doit = Doit->init;

my $Build_PL_file_contents = do {
    open my $fh, '<', 'Build.PL'
	or error "Error opening Build.PL: $!";
    local $/ = undef;
    <$fh>;
};
my $Build_PL_md5hex = md5_hex $Build_PL_file_contents;

if (basename($0) eq 'Build.PL') {
    if (@ARGV) {
	error "Extra arguments found: '@ARGV'";
    }
    {
	if (-l "Build") { # formerly this used to be a symlink
	    $doit->unlink("Build");
	}
	$doit->write_binary('Build', <<"EOF" . $Build_PL_file_contents);
#! $Config{perlpath}
# MD5: $Build_PL_md5hex
EOF
	$doit->chmod(0755, 'Build');
    }
    exit;
}

# Check if Build is up-to-date (md5 check, no timestamp check)
{
    open my $fh, '<', $0
	or error "Can't open $0: $!";
    my $shebang = <$fh>;
    my $md5_line = <$fh>;
    if (my($old_md5hex) = $md5_line =~ m{^# MD5: (\S+)}) {
	if ($old_md5hex ne $Build_PL_md5hex) { 
	    my $perl;
	    if (($perl) = $shebang =~ m{^#!\s*(.*)}) {
		# parsed it
	    } else {
		warning "Cannot parse perl interpreter path out of '$shebang', fallback to 'perl'";
		$perl = "perl";
	    }
	    error "Build.PL changed, please run '$perl Build.PL' again";
	}
    } else {
	error "Unexpected: no MD5 found in '$md5_line'";
    }
}

require Getopt::Long;
my $opt_verbose = 0;
my $opt_uninst = 0;
my $opt_destdir = '';
Getopt::Long::GetOptions(
    "verbose" => \$opt_verbose,
    "uninst" => \$opt_uninst,
    "destdir=s" => \$opt_destdir,
)
    or error "usage: $0 [options]";

my $action = shift || 'build';
if (@ARGV) {
    error "No arguments allowed";
}
{
    no strict 'refs';
    &$action;
}

sub build {
    $doit->make_path('blib/lib');
    require File::Glob;
    for my $file (File::Glob::bsd_glob('lib/*.pm')) { # deeper pms?
	my $dest = 'blib/'.$file;
	if (!-e $dest || -M $dest > -M $file) {
	    $doit->make_path(dirname($dest));
	    $doit->system('cp', $file, $dest);
	}
    }
}

sub clean {
    $doit->remove_tree('blib');
}

sub test {
    $doit->system('prove', '-l', 't'); # use right perl?
}

sub cover {
    $doit->system('prove', '--exec', "$^X -Ilib -MDevel::Cover", 't');
    $doit->system('cover');
}

sub show_cover {
    cover();
    my $browser = $^O eq 'darwin' ? 'open' : 'firefox';
    $doit->system($browser, "$FindBin::RealBin/cover_db/coverage.html");
}

sub install {
    build();
    # XXX check if test suite was run?

    # MOD_INSTALL = $(ABSPERLRUN) -MExtUtils::Install -e 'install([ from_to => {@ARGV}, verbose => '\''$(VERBINST)'\'', uninstall_shadows => '\''$(UNINST)'\'', dir_mode => '\''$(PERM_DIR)'\'' ]);' --
    # $(MOD_INSTALL) \
    # 		read "$(PERL_ARCHLIB)/auto/$(FULLEXT)/.packlist" \
    # 		write "$(DESTINSTALLARCHLIB)/auto/$(FULLEXT)/.packlist" \
    # 		"$(INST_LIB)" "$(DESTINSTALLPRIVLIB)" \
    # 		"$(INST_ARCHLIB)" "$(DESTINSTALLARCHLIB)" \
    # 		"$(INST_BIN)" "$(DESTINSTALLBIN)" \
    # 		"$(INST_SCRIPT)" "$(DESTINSTALLSCRIPT)" \
    # 		"$(INST_MAN1DIR)" "$(DESTINSTALLMAN1DIR)" \
    # 		"$(INST_MAN3DIR)" "$(DESTINSTALLMAN3DIR)"

    require Data::Dumper;
    require ExtUtils::Install;
    my $FULLEXT = 'Doit';
    my $INST_LIB = 'blib/lib';
    my $INST_ARCHLIB = 'blib/arch';
    my $INST_BIN = 'blib/bin';
    my $INST_SCRIPT = 'blib/script';
    my $INST_MAN1DIR = 'blib/man1';
    my $INST_MAN3DIR = 'blib/man3';
    my $PERM_DIR = '755';
    my @euii_args = (
	from_to => {
	    read          => "$Config{archlib}/auto/$FULLEXT/.packlist",
	    write         => "$opt_destdir$Config{installarchlib}/auto/$FULLEXT/.packlist",
	    $INST_LIB     => "$opt_destdir$Config{installprivlib}",
	    $INST_ARCHLIB => "$opt_destdir$Config{installarchlib}",
	    $INST_BIN     => "$opt_destdir$Config{installbin}",
	    $INST_SCRIPT  => "$opt_destdir$Config{installscript}",
	    $INST_MAN1DIR => "$opt_destdir$Config{installman1dir}",
	    $INST_MAN3DIR => "$opt_destdir$Config{installman3dir}",
	},
	verbose           => $opt_verbose,
	uninstall_shadows => $opt_uninst,
	dir_mode          => $PERM_DIR,
    );
    if ($doit->is_dry_run) {
	info "Would run ExtUtils::Install::install " . Data::Dumper::Dumper(@euii_args);
    } else {
	info "Run ExtUtils::Install::install " . Data::Dumper::Dumper(@euii_args);
	ExtUtils::Install::install([@euii_args]);
    }
}

__END__
