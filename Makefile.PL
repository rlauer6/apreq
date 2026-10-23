require 5.006;

use strict;
use warnings;

use Getopt::Long qw(GetOptions);
use Config;

use constant PERL_PATH => $Config{perlpath};  # XXX
use constant WIN32     => ( $^O =~ /Win32/ );

sub test_prereq {
  system( PERL_PATH, "build/version_check.pl", @_ ) == 0
    or warn "Please upgrade $_[0] first.\n";
}

test_prereq perl => PERL_PATH;

my %opts;
undef @opts{
  qw(with-apache2-apxs with-apache1-apxs with-apache2-src
    with-perl with-apache2-httpd
    with-apr-config with-apu-config apxs
    with-expat with-mm-opts)
};

undef @opts{qw(with-apache2)} if (WIN32);

my @flags = qw/enable-maintainer-mode enable-perl-glue disable-perl-glue/;
push @flags, qw/debug/ if (WIN32);
my %args;
# grab from @ARGV only the options that we expect
GetOptions( \%args, ( map "$_=s", keys %opts ), @flags );

$args{"with-perl"} = PERL_PATH;
my $opts = "";
$opts .= "--enable-maintainer-mode " if $args{"enable-maintainer-mode"};

unless ( exists $args{"disable-perl-glue"} ) {
  $opts .= "--enable-perl-glue ";
  test_prereq "mod_perl2";
  test_prereq "Apache::Test";
  test_prereq "ExtUtils::MakeMaker";
  test_prereq "ExtUtils::XSBuilder";
  test_prereq "Test::More";
}

$opts .= "--debug " if ( WIN32 and $args{debug} );

delete @args{@flags};
$args{"with-apache2-apxs"} = delete $args{apxs}
  if exists $args{apxs} and not exists $args{"with-apache2-apxs"};
$args{"with-apache2-apxs"} ||= eval {
  require Apache2::Build;
  Apache2::Build->build_config->{MP_APXS};
};

my ( @perl_opts, @mm_opts );

for my $arg (@ARGV) {
  if ( $arg =~ /^[A-Za-z_][A-Za-z0-9_]*=/ ) {
    push @mm_opts, $arg;
  }
  else {
    push @perl_opts, $arg;
  }
}

if (@mm_opts) {
  my $mm_opts = join ' ', @mm_opts;

  if ( exists $args{'with-mm-opts'} ) {
    $args{'with-mm-opts'} .= " $mm_opts";
  }
  else {
    $args{'with-mm-opts'} = $mm_opts;
  }
}

if (@perl_opts) {
  $args{'with-perl-opts'} = join ' ', @perl_opts;
}

if (WIN32) {
  require File::Basename;
  require File::Spec;
  unless ( $args{'with-apache2'} ) {
    my @candidates = qw(with-apache2-apxs with-apache2-httpd
      with-apr-config with-apu-config);
    foreach my $opt (@candidates) {
      my $c = delete $args{$opt};
      next unless $c;
      ( my $dir = File::Basename::dirname($c) ) =~ s{(\\|/)bin}{};
      if ( -d $dir ) {
        $args{'with-apache2'} = $dir;
        last;
      }
    }
    unless ( $args{'with-apache2'} ) {
      my $mp_ap_prefix = eval { Apache2::Build->build_config->{MP_AP_PREFIX}; };
      if ( $mp_ap_prefix and -d $mp_ap_prefix ) {
        $args{'with-apache2'} = $mp_ap_prefix;
      }
    }
  }
  unless ( defined $args{'with-apache2-apxs'} ) {
    $args{'with-apache2-apxs'} = File::Spec->catfile( $args{'with-apache2'}, 'bin', 'apxs.bat' );
  }
  my @opts = map {qq/--$_="$args{$_}"/} keys %args;
  push @opts, ( split ' ', $opts );
  my @args = ( PERL_PATH, 'win32/Configure.pl', @opts );
  print "@args\n";
  system(@args) == 0 or die "system @args failed: $?";
}
else {
  $opts .= join " ", map {qq/--$_="$args{$_}"/} keys %args;
  my $cmd = "./configure $opts";
  print "$cmd\n";

  system($cmd) == 0
    or die "Configuration failed: $?";

  my $meta_file = 'META.yml';

  if ( !-f $meta_file ) {
    open my $makefile, '<', 'Makefile'
      or die "Cannot open Makefile: $!";

    my $version;

    while ( my $line = <$makefile> ) {
      if ( $line =~ /^PACKAGE_VERSION\s*=\s*(\S+)/ ) {
        $version = $1;
        last;
      }
    }

    close $makefile;

    die 'Cannot determine PACKAGE_VERSION from Makefile'
      if !defined $version;

    open my $generator, '-|', PERL_PATH, 'build/version_check.pl', "-version=$version"
      or die "Cannot execute metadata generator: $!";
    my $tmp_file = "$meta_file.$$";

    open my $output, '>', $tmp_file
      or die "Cannot create $tmp_file: $!";

    while ( my $line = <$generator> ) {
      print {$output} $line
        or die "Cannot write $tmp_file: $!";
    }

    close $output
      or die "Cannot close $tmp_file: $!";

    close $generator
      or die 'Metadata generation failed';

    require CPAN::Meta;
    CPAN::Meta->load_file($tmp_file);

    rename $tmp_file, $meta_file
      or die "Cannot rename $tmp_file to $meta_file: $!";
  }

  require CPAN::Meta;

  my $meta = CPAN::Meta->load_file($meta_file);

  $meta->save('MYMETA.yml');
  $meta->save('MYMETA.json');
}
