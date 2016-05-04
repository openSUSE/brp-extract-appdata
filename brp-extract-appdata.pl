#! /usr/bin/perl

# Copyright (c) 2012 Stephan Kulow, SUSE Linux Products GmbH

# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:

# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#
# find appdata files and extract them for later processing
#
use File::Basename;
use File::Find;
use MIME::Base64;
use Encode;

use strict;

my $basedir=dirname($ENV{'RPM_SOURCE_DIR'}) . "/OTHER";

my $outputfile = "$basedir/$ENV{'RPM_PACKAGE_NAME'}.applications";

if (! -f "/.buildenv") {
  # this looks fishy, skip it
  print "WARNING: I better not trim without a /.buildenv around\n";
  exit(0);
}

if (! -w "$basedir") {
  print "WARNING: Can't write to $basedir, skipping\n";
  exit(0);
}

open(OUTPUT, '>', $outputfile);

chdir("/" . $ENV{'RPM_BUILD_ROOT'});

my @icondirs;
for my $prefix (qw{/usr /opt/kde3 usr opt/kde3}) {
   for my $suffix (qw{pixmaps icons/hicolor icons/crystalsvg icons/gnome}) {
      push @icondirs, "$prefix/share/$suffix" if -d "$prefix/share/$suffix";
   }
}

sub slurp {
  return undef unless  open (my $f, '<', $_[0]);
  my $content = do { local $/; <$f> };
  close $f;
  return $content;
}

sub parse_desktop_data {
  my ($filename) = @_;
  open (my $f, '<', $filename) or return {};
  my $indesktopentry = 0;
  my %res;
  while (<$f>) {
    chomp;
    if (/^\[Desktop Entry\]\s*$/) {
      $indesktopentry++;
      next;
    }
    $indesktopentry++ if $indesktopentry && /^\[/;
    next unless $indesktopentry == 1;
    next unless (m/^([^=]*)=(.*)$/);
    my ($k, $v) = ($1, $2);
    $k =~ s/^([^\[]*)/lc($1)/e;
    $res{$k} = $v;
  }
  return \%res;
}

sub get_icon_data {
  my ($iconname) = @_;

  my @locs;
  find( { wanted => sub { push @locs, $_ if /\/$iconname(?:.png|.svg|.svgz|.xpm)?$/ }, no_chdir => 1}, @icondirs);

  my %have;
  my @res;
  for my $loc (sort @locs) {
    my $fn = $loc;
    $fn =~ s/^\/?/\//;
    next if $have{$fn};
    my $content = slurp($loc);
    next unless $content;
    push @res, [ $fn, encode_base64($content) ];
    $have{$fn} = 1;
  }
  return \@res;
}

sub escape {
  my ($d) = @_;
  $d =~ s/&/&amp;/sg;
  $d =~ s/</&lt;/sg;
  $d =~ s/>/&gt;/sg;
  $d =~ s/"/&quot;/sg;
  Encode::_utf8_on($d);
  $d = encode('UTF-8', $d, Encode::FB_XMLCREF);
  Encode::_utf8_off($d);
  $d =~ s/[\000-\010\013\014\016-\037\177]//g;	# can't have those...
  return $d;
}

sub read_and_extend_appdata {
  my ($appdatafile) = @_;

  my $content = slurp($appdatafile);
  return undef unless $content;
  $content =~ s/\n?$/\n/s;	# make sure file ends with a nl
  $appdatafile =~ s/.*appdata\///;
  my $dd = {};
  if ( $content =~ /<id(?: type=\"desktop\")?>(.*)</m ) {
    $dd = parse_desktop_data("usr/share/applications/$1");
    $content =~s/(<application .*)$/<component type="desktop">/m;
    $content =~s/<id(?: type=\"desktop\")?>(.*)/<id>$1/m;
    $content =~s/\/application>/\/component>/m;
  }
  $content =~ s/(<\/id>.*)$/$1\n  <pkgname>appdata($appdatafile)<\/pkgname>/m;
  if ($dd->{'keywords'} && $content !~ /<keywords/) {
    my $xml = "  <keywords>\n";
    $xml .= "    <keyword>".escape($_)."</keyword>\n" for split(/\s*;\s*/, $dd->{'keywords'});
    $xml .= "  </keywords>\n";
    $content =~ s/^(\s*<\/(?:application|component)>)/$xml$1/m;
  }
  if ($dd->{'icon'} && $content !~ /<icon/) {
    my $idata = get_icon_data($dd->{'icon'});
    if ($idata && @$idata) {
      my $xml = "  <icon type='embedded'>\n    <name>".escape($dd->{'icon'})."</name>\n";
      $xml .= "    <filecontent file='".escape($_->[0])."'>\n$_->[1]    </filecontent>\n" for @$idata;
      $xml .= "  </icon>\n";
      $content =~ s/^(\s*<\/(?:application|component)>)/$xml$1/m;
    }
  }
  return $content;
}

my @appdatas;
find( { wanted => sub { push @appdatas, $_ if /\.appdata\.xml$/ || /\.metainfo.xml$/ } , no_chdir => 1}, "usr/share/appdata/");

my $output = '';

for my $appdata (@appdatas) {
  my $c = read_and_extend_appdata($appdata);
  next unless $c;
  $c =~ s/^<\?xml[^\n]*\n//s;
  $c =~ s/\n?$/\n/s;
  $c =~ s/^(\s*<)/  $1/mg;
  $output .= $c;
}

my $type = 'applications';
$type = $1 if $output =~ /(application|component)/s;
print OUTPUT "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
print OUTPUT $output;
print OUTPUT "\n";
