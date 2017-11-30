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
use Doit::Extcmd qw(is_in_path);
use Doit::Log;
use Doit::Util qw(in_directory);

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

sub test_xt {
    $doit->system(_prove_path(), '-b', 'xt'); # use right perl?
}

sub test_installed {
    my $t_dir = "$FindBin::RealBin/t";
    chdir "/"
	or error "Cannot chdir to /: $!";
    $doit->system(_prove_path(), $t_dir);
}

sub test_in_docker {
    my $distro_spec = $ENV{DISTRO_SPEC}; # XXX this should be a proper option!
    if (!$distro_spec || $distro_spec !~ m{^.*:.*$}) {
	error "Please set DISTRO_SPEC environment variable to something like 'debian:jessie'";
    }
    for my $tool (qw(docker)) {
	$doit->qx('which', $tool); # existence check
    }
    require File::Temp;
    my $dir = File::Temp::tempdir("Doit_test_in_docker_XXXXXXXX", TMPDIR => 1, CLEANUP => 1);
    $doit->write_binary("$dir/Dockerfile", <<"EOF");
FROM $distro_spec

ENV DEBIAN_FRONTEND noninteractive 

RUN apt-get update && apt-get install -y --no-install-recommends \\
    libipc-run-perl \\
    libnet-openssh-perl \\
    sudo \\
    rsync

EOF
    in_directory {
	$doit->system(qw(docker build -t doit-test .));
	$doit->system(
		      qw(docker run), '-v', "$FindBin::RealBin:/data:ro", qw(doit-test),
		      'sh', '-c', 'rsync -a --cvs-exclude --exclude=blib /data/ /tmp/Doit/ && cd /tmp/Doit && perl Build.PL && ./Build && ./Build generate_META_json && ./Build test && ./Build test_xt'
		     );
    } $dir;
}

sub test_kwalitee ($) {
    my($distdir) = @_;
    # If cwd is used then more tests fail,
    # because META files are not available here.
    $distdir = $FindBin::RealBin if !defined $distdir;

    if (eval { require Test::Kwalitee; 1 }) {
	in_directory {
	    local $ENV{RELEASE_TESTING} = 1;
	    eval { $doit->system($^X, '-MTest::More', '-MTest::Kwalitee=kwalitee_ok', '-e', 'kwalitee_ok(qw(-has_manifest)); done_testing') };
	} $distdir;
    }
}

sub distdir {
    require File::Basename;
    require File::Temp;
    my $tempdir = File::Temp::tempdir(CLEANUP => 1);
    my $Doit_VERSION = _get_Doit_VERSION();
    my $distdir = "$tempdir/Doit-$Doit_VERSION";
    $doit->mkdir($distdir);
    for my $line (split /\n/, $doit->info_qx({quiet=>1}, 'git', 'ls-files')) {
	next if ($line =~ m{^(\.travis\.yml|appveyor\.yml)$});
	# XXX maybe implement also MANIFEST.SKIP?
	my $dirname = File::Basename::dirname($line);
	if ($dirname ne '.') {
	    $doit->make_path("$distdir/$dirname");
	}
	$doit->copy($line, "$distdir/$dirname/");
    }

    generate_META_json("$distdir/META.json");
    generate_META_yml("$distdir/META.yml" );

    test_kwalitee($distdir);

    $distdir;
}

sub dist {
    my $distdir = distdir();
    my $Doit_VERSION = _get_Doit_VERSION();
    require Cwd;
    require File::Basename;
    my $tarfile = Cwd::getcwd() . "/Doit-" . $Doit_VERSION . ".tar.gz";
    if (-e $tarfile) {
	error "$tarfile already exists";
    }
    in_directory {
	$doit->system('tar', 'cfvz', $tarfile, File::Basename::basename($distdir));
    } "$distdir/..";
}

sub cover {
    {
	no warnings 'uninitialized';
	local $ENV{PERL5LIB} .= ($ENV{PERL5LIB} ne '' ? ':' : '') . "$FindBin::RealBin/lib";
	local $ENV{PERL5OPT} .= ($ENV{PERL5OPT} ne '' ? ' ' : '') . '-MDevel::Cover';
	$doit->system(_prove_path(), '--exec', $^X, 't');
    }
    $doit->system(_cover_path());
}

sub show_cover {
    cover();
    my $browser = $^O eq 'darwin' ? 'open' : is_in_path('xdg-open') ? 'xdg-open' : 'firefox';
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
    my $euii_args_dump = Data::Dumper->new([{ @euii_args }],[qw()])->Indent(1)->Useqq(1)->Sortkeys(1)->Terse(1)->Dump;
    if ($doit->is_dry_run) {
	info "Would run ExtUtils::Install::install with parameters\n" . $euii_args_dump;
    } else {
	info "Run ExtUtils::Install::install with parameters\n" . $euii_args_dump;
	ExtUtils::Install::install([@euii_args]);
    }
}

sub git_tag {
    $doit->add_component('git');

    my $status = $doit->git_short_status;
    if ($status eq '<<') {
	error 'Working directory has uncomitted changes: ' . `git status`;
    }
    if ($status eq '*') {
	error 'Working directory has files not under git control (and not in .gitignore or .git/info/exclude): ' . `git status`;
    }

    my $Doit_VERSION = _get_Doit_VERSION();

    my $out = $doit->info_qx(qw(git tag --list), $Doit_VERSION);
    if (defined $out && $out ne '') {
	error "A git tag $Doit_VERSION already exists";
    }

    $doit->system(qw(git tag -a -m), "tag $Doit_VERSION release", $Doit_VERSION);
}

sub _get_Doit_VERSION () {
    my $Doit_VERSION = $Doit::VERSION;
    if (!defined $Doit_VERSION) {
	error 'Fatal: Doit.pm does not define a version';
    }
    if ($Doit_VERSION !~ m{^\d+\.\d+$}) {
	error "Doit.pm VERSION $Doit_VERSION does not look like expected";
    }
    $Doit_VERSION;
}

sub _generate_META ($;$) {
    my($destfile, $version) = @_;

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
    if ($doit->is_dry_run) {
	info "Would create $destfile" . (defined $version ? " (version $version)" : "") . " (dry-run)";
    } else {
	$meta->save($destfile, (defined $version ? { version => $version } : ()));
    }
}

sub generate_META_json (;$) {
    my $destfile = shift || 'META.json';
    _generate_META $destfile;
}

sub generate_META_yml (;$) {
    my $destfile = shift || 'META.yml';
    _generate_META $destfile, 1;
}

# XXX the debian package build functionality should go into
# a separate Doit component

sub debian_package {
    _debian_package('--depends' => 'perl, libnet-openssh-perl, libipc-run-perl', '--add-distro-version' => '1');
}

sub _debian_package {
    my(%opts) = @_;

    for my $tool (qw(dh-make-perl)) { # XXX maybe add git here?
	$doit->qx('which', $tool); # existence check
    }

    my $distdir = distdir();

    my $version = delete $opts{'--version'};
    my $add_distro_version = delete $opts{'--add-distro-version'};
    if (!defined $version) {
	chomp(my $git_describe = eval { $doit->info_qx('git', 'describe') }); # XXX what if this fails? Optionally made fatal?
	if (defined $git_describe) {
	    if ($git_describe =~ m{^([0-9\.]+)$}) {
		$version = $1;
	    } elsif ($git_describe =~ m{^([0-9\.]+)-(\d+)-g(.*)}) {
		$version = $1."+git".$2."+".$3."-1"; # XXX make "1" configurable?
	    } else {
		error "Cannot parse output from git describe: '$git_describe'";
	    }
	    if ($add_distro_version) {
		chomp(my $dist_id = $doit->qx({quiet=>1}, 'lsb_release', '-si'));
		chomp(my $rel     = $doit->qx({quiet=>1}, 'lsb_release', '-sr'));
		if ($dist_id eq 'Debian') {
		    $rel =~ s{^(\d+).*}{$1};
		    $version .= "+deb${rel}u${add_distro_version}";
		} elsif ($dist_id eq 'LinuxMint') {
		    $version .= "+linuxmint${rel}u${add_distro_version}";
		} elsif ($dist_id eq 'Ubuntu') {
		    $version .= "~ubuntu${rel}.${add_distro_version}";
		} else {
		    error "No distro version support for '$dist_id'";
		}
	    }
	} else {
	    warning "No information using git-describe available --- use automatic version detection";
	}
    }

    my $deb;
    in_directory {
	$doit->system(qw(dh-make-perl --build --vcs none), (defined $version ? ('--version', $version) : ()), %opts);
	require File::Glob;
	my(@debs) = File::Glob::bsd_glob("$distdir/../*.deb");
	if (@debs != 1) {
	    error "Expecting exactly one generated .deb, but got: <@debs>\n";
	}
	$deb = $debs[0];
    } $distdir;
    $doit->copy($deb, basename($deb));
    print basename($deb), "\n";
}

sub debian_package_with_docker {
    my $distro_spec = $ENV{DISTRO_SPEC}; # XXX this should be a proper option!
    if (!$distro_spec || $distro_spec !~ m{^.*:.*$}) {
	error "Please set DISTRO_SPEC environment variable to something like 'debian:jessie'";
    }
    for my $tool (qw(docker)) {
	$doit->qx('which', $tool); # existence check
    }
    require File::Temp;
    my $dir = File::Temp::tempdir("Doit_debian_package_docker_XXXXXXXX", TMPDIR => 1, CLEANUP => 1);
    my $use_workdir = $ENV{USE_WORKDIR}; # XXX this should be a proper option
    if ($use_workdir) {
	# no --cvs-exclude --- git-describe has to work
	$doit->system('rsync', '-a', '--exclude=blib', '.', $dir);
    } else {
	$doit->add_component('git');
	$doit->git_repo_update(
	    repository => $FindBin::RealBin,
	    directory  => $dir,
	    # no: we need the full history for correct git version calculation: clone_opts => [qw(--depth=1)],
	);
    }
    $doit->write_binary("$dir/Dockerfile", <<"EOF");
FROM $distro_spec

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
    in_directory {
	(my $label = $distro_spec) =~ s{:}{-}g;
	$label = "doit-deb-$label";
	$doit->system(qw(docker build -t), $label, qw(.));
	$doit->system(
		      qw(docker run), '-v', "$dir:/data", qw(-v /tmp:/pkg), $label,
		      'sh', '-c', 'cd /data && perl Build.PL && ./Build debian_package && cp *.deb /pkg'
		     );
    } $dir;
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
	my $preamble = <<"EOF";
#! $Config{perlpath}
# MD5: $Build_PL_md5hex
EOF
	$preamble .= $argv_serialized;
	$doit->write_binary({quiet=>1}, 'Build', $preamble . qq{# line 1 "Build.PL"\n} . $Build_PL_file_contents);
	$doit->chmod(0755, 'Build');
    }
    exit;
}

__END__
