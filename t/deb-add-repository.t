#!/usr/bin/perl -w
# -*- cperl -*-

use strict;
use warnings;
use FindBin;
use lib $FindBin::RealBin;

use Test::More;

use Doit;
use Doit::Deb;

sub convert { Doit::Deb::_convert_sources_to_list(shift) }

# --- Simple repo ---
my $src1 = <<'EOF';
Types: deb
URIs: http://deb.debian.org/debian
Suites: stable
Components: main
EOF

is convert($src1),
   "deb http://deb.debian.org/debian stable main\n",
   "single deb line generated";

# --- Multiple types ---
my $src2 = <<'EOF';
Types: deb deb-src
URIs: http://deb.debian.org/debian
Suites: stable
Components: main
EOF

is convert($src2),
   "deb http://deb.debian.org/debian stable main\n".
   "deb-src http://deb.debian.org/debian stable main\n",
   "deb and deb-src generated";

# --- Multiple suites and components ---
my $src3 = <<'EOF';
Types: deb
URIs: http://deb.debian.org/debian
Suites: stable stable-updates
Components: main contrib
EOF

is convert($src3),
   "deb http://deb.debian.org/debian stable main contrib\n".
   "deb http://deb.debian.org/debian stable-updates main contrib\n",
   "multiple suites expanded";

# --- With architectures ---
my $src4 = <<'EOF';
Types: deb
URIs: http://deb.debian.org/debian
Suites: stable
Components: main
Architectures: amd64 arm64
EOF

is convert($src4),
   "deb [arch=amd64,arm64] http://deb.debian.org/debian stable main\n",
   "arch option emitted";

# --- With multiple Signed-By ---
my $src5 = <<'EOF';
Types: deb
URIs: http://deb.debian.org/debian
Suites: stable
Components: main
Signed-By: /etc/apt/keyrings/foo.gpg
           /etc/apt/keyrings/bar.gpg
EOF

is convert($src5),
   "deb [signed-by=/etc/apt/keyrings/foo.gpg signed-by=/etc/apt/keyrings/bar.gpg] ".
   "http://deb.debian.org/debian stable main\n",
   "multiple signed-by emitted";

# --- Combined architectures + signed-by ---
my $src6 = <<'EOF';
Types: deb deb-src
URIs: http://deb.debian.org/debian
Suites: stable
Components: main
Architectures: amd64 arm64
Signed-By: /etc/apt/keyrings/foo.gpg
EOF

is convert($src6),
   "deb [arch=amd64,arm64 signed-by=/etc/apt/keyrings/foo.gpg] ".
   "http://deb.debian.org/debian stable main\n".
   "deb-src [arch=amd64,arm64 signed-by=/etc/apt/keyrings/foo.gpg] ".
   "http://deb.debian.org/debian stable main\n",
   "arch + signed-by combined";

done_testing;

__END__
