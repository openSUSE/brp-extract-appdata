#!/usr/bin/perl -w
# read appsteam imput data and distribute the data into the
# matching rpms

use strict;
use Data::Dumper;
use File::Glob;

sub escape {
  my ($d) = @_;
  $d =~ s/&/&amp;/sg;
  $d =~ s/</&lt;/sg;
  $d =~ s/>/&gt;/sg;
  $d =~ s/"/&quot;/sg;
  return $d;
}

my $build_root = $::ENV{BUILD_ROOT} || $::ENV{RPM_BUILD_ROOT} || '/';

my $TOPDIR = '/usr/src/packages';
$TOPDIR = '/.build.packages' if -d "$build_root/.build.packages";

open (ALL_RPMS, "chroot $build_root find $TOPDIR/RPMS/ -name \"*.rpm\" |");
my @rpms = <ALL_RPMS>;
chomp @rpms;
close ALL_RPMS;

my @appdata = glob("$build_root$TOPDIR/OTHER/*.applications");
if (@appdata != 1) {
  print STDERR "DEBUG: there is not a single *.applications file\n";
  exit 0;
}
my $appdata = shift @appdata;
open(APPDATA, '<', $appdata) || die "can't open $appdata\n";
my $content = do { local $/; <APPDATA> };
close APPDATA;
unlink $appdata;

# remove start and end tags
$content =~ s/.*\n<(?:applications|components)[^\n]*>\n//s;
$content =~ s/<\/(?:applications|components)>\n$//s;

# split into application chunks
my @appdatas = split(/<(?:application|component)/, $content);
for (@appdatas) {
  $_ = "  <component$_";
  s/<\/application/<\/component/;
}

my %appmatches;
for my $ad (@appdatas) {
  next unless $ad =~ /^    <pkgname>appdata\((.*)\)<\/pkgname>$/m;
  $appmatches{"/usr/share/appdata/$1"} = $ad;
}
exit 0 unless %appmatches;

my %appresults;
for my $rpm (@rpms) {
  next if $rpm =~ m/-debuginfo/ || $rpm =~ m/-debugsource/ || $rpm =~ /src\.rpm$/;
  open (FILES, "chroot $build_root rpm -qp --qf '%{NAME} [%{FILENAMES}\n]' $rpm|");
  my @files = <FILES>;
  chomp @files;
  close FILES;
  # ignore empty rpm as rpmlint will catch them
  @files = grep {!/^\(none\)/} @files;
  for my $file (@files) {
    next unless $file =~ /^(\S+) (.*)$/;
    my $rpmname = $1;
    my $rpmfile = $2;
    my $ad = $appmatches{$rpmfile};
    next unless $ad;
    my $rpmnamex = escape($rpmname);
    next unless $ad =~ s/^    <pkgname>appdata\((.*)\)<\/pkgname>$/    <pkgname>$rpmnamex<\/pkgname>/m;
    push @{$appresults{$rpmname}}, $ad;
  }
}

for my $rpmname (sort keys %appresults) {
  my $output = "$build_root$TOPDIR/OTHER/$rpmname.appdata.xml";
  open(APPDATA, '>', $output) || die "can't write to $output";
  print APPDATA "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
  my $type = 'component';
  $type = $1 if ($appresults{$rpmname}->[0] || '') =~ /(application|component)/;
  print APPDATA $_ for @{$appresults{$rpmname}};
  close APPDATA;
}
