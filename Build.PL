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

for (@ARGV) {
    if (/.*=.*/) { # looks like oldfashioned options (e.g. "installdirs=vendor")
	s/^/--/;
    }
}

if (basename($0) eq 'Build.PL') {
    _Build_PL_mode();
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
my %opt = (verbose => 0, uninst => 0, destdir => '', create_packlist => 1);
$Build_PL::ARGV=$Build_PL::ARGV if 0; # cease -w
@ARGV = (@$Build_PL::ARGV, @ARGV);
Getopt::Long::GetOptions(
    \%opt,
    'allow_mb_mismatch=i',
    'config=s%',
    'create_packlist=i',
    'destdir=s',
    'installdirs=s',
    'install_path=s%',
    'prefix=s',
    'uninst:1',
    'verbose:1',
    'versionlib=s',
    'version=s',
)
    or error "usage: $0 [options]";

my $action = shift || 'build';
$action =~ s/-/_/g;
if (@ARGV) {
    error "No arguments allowed";
}
{
    no strict 'refs';
    &$action;
}

sub build {
    $doit->make_path('blib/lib');
    require File::Find;
    my @pm_files;
    File::Find::find(sub { no warnings 'once'; push @pm_files, $File::Find::name if /\.pm$/ && -f $_ }, "lib");
    for my $file (@pm_files) {
	my $dest = 'blib/'.$file;
	if (!-e $dest || -M $dest > -M $file) {
	    $doit->make_path(dirname($dest));
	    $doit->copy($file, $dest);
	}
    }
}

sub clean {
    $doit->remove_tree('blib');
}

sub realclean { &clean }

sub test {
    $doit->system(_prove_path(), '-b', 't'); # use right perl?
}

sub test_installed {
    my $t_dir = "$FindBin::RealBin/t";
    chdir "/"
	or error "Cannot chdir to /: $!";
    $doit->system(_prove_path(), $t_dir);
}

sub cover {
    $doit->system(_prove_path(), '--exec', "$^X -Ilib -MDevel::Cover", 't');
    $doit->system(_cover_path());
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

    # for a perl install:
    # 		read "$(PERL_ARCHLIB)/auto/$(FULLEXT)/.packlist" \
    # 		write "$(DESTINSTALLARCHLIB)/auto/$(FULLEXT)/.packlist" \
    # 		"$(INST_LIB)" "$(DESTINSTALLPRIVLIB)" \
    # 		"$(INST_ARCHLIB)" "$(DESTINSTALLARCHLIB)" \
    # 		"$(INST_BIN)" "$(DESTINSTALLBIN)" \
    # 		"$(INST_SCRIPT)" "$(DESTINSTALLSCRIPT)" \
    # 		"$(INST_MAN1DIR)" "$(DESTINSTALLMAN1DIR)" \
    # 		"$(INST_MAN3DIR)" "$(DESTINSTALLMAN3DIR)"

    # for a site install:
    #           read "$(SITEARCHEXP)/auto/$(FULLEXT)/.packlist" \
    #           write "$(DESTINSTALLSITEARCH)/auto/$(FULLEXT)/.packlist" \
    #           "$(INST_LIB)" "$(DESTINSTALLSITELIB)" \
    #           "$(INST_ARCHLIB)" "$(DESTINSTALLSITEARCH)" \
    #           "$(INST_BIN)" "$(DESTINSTALLSITEBIN)" \
    #           "$(INST_SCRIPT)" "$(DESTINSTALLSITESCRIPT)" \
    #           "$(INST_MAN1DIR)" "$(DESTINSTALLSITEMAN1DIR)" \
    #           "$(INST_MAN3DIR)" "$(DESTINSTALLSITEMAN3DIR)"
 
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
	    (
		($opt{installdirs}||'') eq 'core'
		?
		(
		    read          => "$Config{archlib}/auto/$FULLEXT/.packlist",
		    ($opt{create_packlist} ? (write => "$opt{destdir}$Config{installarchlib}/auto/$FULLEXT/.packlist") : ()),
		    $INST_LIB     => "$opt{destdir}$Config{installprivlib}",
		    $INST_ARCHLIB => "$opt{destdir}$Config{installarchlib}",
		    $INST_BIN     => "$opt{destdir}$Config{installbin}",
		    $INST_SCRIPT  => "$opt{destdir}$Config{installscript}",
		    $INST_MAN1DIR => "$opt{destdir}$Config{installman1dir}",
		    $INST_MAN3DIR => "$opt{destdir}$Config{installman3dir}",
		)
		:
		($opt{installdirs}||'') eq 'vendor'
		?
		(
		    read          => "$Config{vendorlib}/auto/$FULLEXT/.packlist",
		    ($opt{create_packlist} ? (write => "$opt{destdir}$Config{installarchlib}/auto/$FULLEXT/.packlist") : ()),
		    $INST_LIB     => "$opt{destdir}$Config{installvendorlib}",
		    $INST_ARCHLIB => "$opt{destdir}$Config{installvendorarch}",
		    $INST_BIN     => "$opt{destdir}$Config{installvendorbin}",
		    $INST_SCRIPT  => "$opt{destdir}$Config{installvendorscript}",
		    $INST_MAN1DIR => "$opt{destdir}$Config{installvendorman1dir}",
		    $INST_MAN3DIR => "$opt{destdir}$Config{installvendorman3dir}",
		)
		: # default is site
		(
		    read          => "$Config{sitearchexp}/auto/$FULLEXT/.packlist",
		    ($opt{create_packlist} ? (write => "$opt{destdir}$Config{installarchlib}/auto/$FULLEXT/.packlist") : ()),
		    $INST_LIB     => "$opt{destdir}$Config{installsitelib}",
		    $INST_ARCHLIB => "$opt{destdir}$Config{installsitearch}",
		    $INST_BIN     => "$opt{destdir}$Config{installsitebin}",
		    $INST_SCRIPT  => "$opt{destdir}$Config{installsitescript}",
		    $INST_MAN1DIR => "$opt{destdir}$Config{installsiteman1dir}",
		    $INST_MAN3DIR => "$opt{destdir}$Config{installsiteman3dir}",
		)
	    )
	},
	verbose           => $opt{verbose},
	uninstall_shadows => $opt{uninst},
	dir_mode          => $PERM_DIR,
    );
    if ($doit->is_dry_run) {
	info "Would run ExtUtils::Install::install " . Data::Dumper::Dumper(@euii_args);
    } else {
	info "Run ExtUtils::Install::install " . Data::Dumper::Dumper(@euii_args);
	ExtUtils::Install::install([@euii_args]);
    }
}

sub generate_META_json {
    require CPAN::Meta;
    require ExtUtils::MakeMaker;
    my $meta = CPAN::Meta->new({
	version  => 1.4,
	name     => 'Doit',
	author   => 'Slaven Rezic <srezic@cpan.org>',
	abstract => 'a scripting framework',
	license  => 'perl',
	version  => MM->parse_version("$FindBin::RealBin/lib/Doit.pm"),
	prereqs  => {
	    runtime => {
		recommends => {
		    'IPC::Run'     => 0,
		    'Net::OpenSSH' => 0,
		},
	    },
	},
    });
    $meta->save("META.json");
}

# XXX the debian package build functionality should go into
# a separate Doit component

sub debian_package {
    _debian_package('--depends' => 'perl, libnet-openssh-perl, libipc-run-perl', '--add-distro-version' => '1');
}

sub _debian_package {
    my(%opts) = @_;

    for my $tool (qw(dh-make-perl rsync)) { # XXX maybe add git here?
	$doit->qx('which', $tool); # existence check
    }

    # XXX optionally support inplace operation without rsync ---
    # useful e.g. for docker builds
    require File::Temp;
    require File::Glob;
    my $dir = File::Temp::tempdir("Doit_debian_package_XXXXXXXX", TMPDIR => 1, CLEANUP => 1);
    $doit->system('rsync', '-a', '--exclude=.git', "$FindBin::RealBin/", "$dir/Doit/");

    my $version = delete $opts{'--version'};
    my $add_distro_version = delete $opts{'--add-distro-version'};
    if (!defined $version) {
	my $git_describe = eval { $doit->info_qx('git', 'describe') }; # XXX what if this fails? Optionally made fatal?
	if (defined $git_describe && $git_describe =~ m{^([0-9\.]+)-(\d+)-g(.*)}) {
	    $version = $1."+git".$2."+".$3."-1"; # XXX make "1" configurable?
	    if ($add_distro_version) {
		chomp(my $dist_id = $doit->qx({quiet=>1}, 'lsb_release', '-si'));
		chomp(my $rel     = $doit->qx({quiet=>1}, 'lsb_release', '-sr'));
		if ($dist_id eq 'Debian') {
		    $rel =~ s{^(\d+).*}{$1};
		    $version .= "+deb${rel}u${add_distro_version}";
		} elsif ($dist_id eq 'LinuxMit') {
		    $version .= "+linuxmint${rel}u${add_distro_version}";
		} elsif ($dist_id eq 'Ubuntu') {
		    $version .= "~ubuntu${rel}.${add_distro_version}";
		} else {
		    error "No distro version support for '$dist_id'";
		}
	    }
	}
    }

    my $deb;
    {
	my $save_pwd = save_pwd2();
	chdir "$dir/Doit" or die "Can't chdir to $dir/Doit: $!";
	$doit->system(qw(dh-make-perl --build --vcs none), (defined $version ? ('--version', $version) : ()), %opts);
	my(@debs) = File::Glob::bsd_glob("$dir/*.deb");
	if (@debs != 1) {
	    error "Expecting exactly one generated .deb, but got: <@debs>\n";
	}
	$deb = $debs[0];
    }
    $doit->system('cp', $deb, basename($deb));
    print basename($deb), "\n";
}

sub debian_package_with_docker {
    my $distro_spec = $ENV{DISTRO_SPEC};
    if (!$distro_spec || $distro_spec !~ m{^.*:.*$}) {
	error "Please set DISTRO_SPEC environment variable to something like 'debian:jessie'";
    }
    for my $tool (qw(docker)) {
	$doit->qx('which', $tool); # existence check
    }
    require File::Temp;
    my $dir = File::Temp::tempdir("Doit_debian_package_docker_XXXXXXXX", TMPDIR => 1, CLEANUP => 1);
    $doit->add_component('git');
    $doit->git_repo_update(
	repository => $FindBin::RealBin,
	directory  => $dir,
	# no: we need the full history for correct git version calculation: clone_opts => [qw(--depth=1)],
    );
    $doit->write_binary("$dir/Dockerfile", <<"EOF");
FROM $distro_spec
MAINTAINER Slaven Rezic "srezic\@cpan.org"

ENV DEBIAN_FRONTEND noninteractive 

RUN apt-get update && apt-get install -y --no-install-recommends \\
    dh-make-perl \\
    lsb-release \\
    rsync \\
    git

# XXX This is depending on the current perl module and should be configurable
RUN apt-get install -y --no-install-recommends \\
    libipc-run-perl \\
    libnet-openssh-perl

EOF
    {
	my $save_pwd = save_pwd2();
	chdir $dir
	    or die "Can't chdir to $dir: $!";
	$doit->system(qw(docker build -t dh-make-perl-build .));
	$doit->system(
		      qw(docker run), '-v', "$dir:/data", qw(-v /tmp:/pkg dh-make-perl-build),
		      'sh', '-c', 'cd /data && perl Build.PL && ./Build debian_package && cp *.deb /pkg'
		     );
    }
}

sub _prove_path {
    my @candidates = ("$Config{bin}/prove", "$Config{bin}/prove$Config{version}");
    if ($^O eq 'MSWin32') {
	unshift @candidates, map { "$_.bat"} @candidates;
    }
    for my $candidate (@candidates) {
	if (-x $candidate) {
	    return $candidate;
	}
    }
    error "No 'prove' for the current perl found";
}

sub _cover_path {
    my @candidates = ("$Config{bin}/cover");
    if ($^O eq 'MSWin32') {
	unshift @candidates, map { "$_.bat"} @candidates;
    }
    for my $candidate (@candidates) {
	if (-x $candidate) {
	    return $candidate;
	}
    }
    error "No 'cover' for the current perl found";
}

sub _Build_PL_mode {
    require Data::Dumper;
    my $argv_serialized = "\n" . '$Build_PL::ARGV = ' . Data::Dumper->new([\@ARGV], [])->Indent(1)->Useqq(1)->Sortkeys(1)->Terse(1)->Dump . ";\n\n";
    {
	if (-l "Build") { # formerly this used to be a symlink
	    $doit->unlink("Build");
	}
	$doit->write_binary('Build', <<"EOF" . $argv_serialized . $Build_PL_file_contents);
#! $Config{perlpath}
# MD5: $Build_PL_md5hex
EOF
	$doit->chmod(0755, 'Build');
    }
    exit;
}

# REPO BEGIN
# REPO NAME save_pwd2 /home/slaven.rezic/src/srezic-repository 
# REPO MD5 d0ad5c46f2276dc8aff7dd5b0a83ab3c

BEGIN {
    sub save_pwd2 {
	require Cwd;
	my $pwd = Cwd::getcwd();
	if (!defined $pwd) {
	    warn "No known current working directory";
	}
	bless {cwd => $pwd}, __PACKAGE__ . '::SavePwd2';
    }
    my $DESTROY = sub {
	my $self = shift;
	if (defined $self->{cwd}) {
	    chdir $self->{cwd}
	        or die "Can't chdir to $self->{cwd}: $!";
	}
    };
    no strict 'refs';
    *{__PACKAGE__.'::SavePwd2::DESTROY'} = $DESTROY;
}
# REPO END

__END__
