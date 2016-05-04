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

use strict;
use XML::Simple;
use Data::Dumper;
use File::Temp;
use MIME::Base64;
use Cwd;
use File::Path;

my %ids;

sub find_perfect_match($)
{
  my ($ref) = @_;
  my @candidates = sort @$ref;
  if (@candidates == 1) {
    return $candidates[0];
  }
  foreach my $size (qw(32 48 64 24 )) {
    my @sized_icons;
    my $pattern = "/$size" . "x$size/";
    for my $can (@candidates) {
      push(@sized_icons,$can) if ($can =~ m/($pattern)/);
    }
    return $sized_icons[0] if (@sized_icons == 1);
    if (@sized_icons) {
      for my $can (@sized_icons) {
	return $can if ($can =~ m,/hicolor/,);
      }
      print "UNKNOWN $size " . join(' , ', @sized_icons) . "\n";
      return $sized_icons[0];
    }
  }
  print "UNKNOWN " . join(' , ', @candidates) . "\n";
  return $candidates[0];
}

sub extract_icon($$)
{
  my ($ref, $tmpdir) = @_;
  my $name = 'fancy';
  my $name = shift @{$ref->{name}};

  return $name unless ($ref->{filecontent});
  my %files;
  my @fcontent = @{$ref->{filecontent}};
  foreach my $icon (@fcontent) {
     $files{$icon->{file}} = $icon->{content};
  }
  my @candidates = keys %files;
  my $best = find_perfect_match(\@candidates);
  my $suffix = $best;
  $suffix =~ s,^.*\.([^.]*)$,$1,;
  open(ICON, ">", "$tmpdir/$name.$suffix"); 
  print ICON decode_base64($files{$best});
  close(ICON);
  #print "$name $best\n";
  return "$name.$suffix";
}

if (@ARGV != 2 || $ARGV[0] eq "--help" || $ARGV[0] eq "-h") {
  print "Usage: $0 <appdata.xml> <outdir>\n";
  print "  It will output appdata.xml and appdata-icon.tar.gz in outdir\n";
  exit(1);
}

my $inputfile = $ARGV[0];
my $outdir = $ARGV[1];

if (! -d $outdir) {
  print "Output directory must exist.\n";
  exit(1);
} 
 
my $xml = XMLin($inputfile, ForceArray => 1) || die "can't parse $inputfile";
my $apps = $xml->{application};
my $tmpdir = mkdtemp("/tmp/icons.XXXXXX");
my @napps;
for my $app ( @$apps) {
  my $id = @{$app->{id}}[0];
  next if defined $ids{$id->{content}};
  $ids{$id->{content}} = 1;
  my $icon = extract_icon(@{$app->{icon}}[0], $tmpdir);
  if ($icon) {
    $app->{icon} = [ { "type" => "cached", "content" => $icon } ];
  } else {
    delete $app->{icon};
  }
  push(@napps, $app);
}

$xml->{version} = "1.0";
$xml->{application} = \@napps;
$xml = XMLout($xml, RootName => "applications");

chdir($outdir) || die "can't change into $outdir";
my $cpwd = getcwd;

chdir($tmpdir);
system("tar", "czf", "$cpwd/app-icons.tar.gz", ".");
chdir($cpwd);
rmtree($tmpdir);
open(XML, ">", "$cpwd/appdata.xml");
print XML "$xml";
close(XML);
