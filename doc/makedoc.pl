#! /usr/bin/perl -w
#
# Copyright (C) 1999-2000 Thomas Roessler <roessler@does-not-exist.org>
# Copyright (C) 2019 Kevin J. McCarthy <kevin@8t8.us>
#
#     This program is free software; you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation; either version 2 of the License, or
#     (at your option) any later version.
#
#     This program is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with this program; if not, write to the Free Software
#     Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

# This program was translated from the C version (makedoc.c).
# So it looks like "c'ish perl" because it is, plus my perl is rusty ;-)


# Documentation line parser notes:
#
# The format is very remotely inspired by nroff. Most important, it's
# easy to parse and convert, and it was easy to generate from the SGML
# source of mutt's original manual.
#
# - \fI switches to italics
# - \fB switches to boldface
# - \fC swtiches to a literal string
# - \fP switches to normal display
# - .dl on a line starts a definition list (name taken from HTML).
# - .dt starts a term in a definition list.
# - .dd starts a definition in a definition list.
# - .de on a line finishes a definition list.
# - .il on a line starts an itemized list
# - .dd starts an item in an itemized list
# - .ie on a line finishes an itemized list
# - .ts on a line starts a "tscreen" environment (name taken from SGML).
# - .te on a line finishes this environment.
# - .pp on a line starts a paragraph.
# - \$word will be converted to a reference to word, where appropriate.
#   Note that \$$word is possible as well.
# - '. ' in the beginning of a line expands to two space characters.
#   This is used to protect indentations in tables.
#

use strict;
use warnings;
use Getopt::Std;

# Output formats
my $F_CONF = 1;
my $F_MAN  = 2;
my $F_SGML = 3;

my $OutputFormat;

# docstatus flags, used by print_it()
my $D_INIT = (1 << 0);   # init
my $D_NL   = (1 << 1);   # (usually) on a new line
my $D_NP   = (1 << 2);   # new paragraph           ".pp"
my $D_PA   = (1 << 3);   # inside paragraph        ".pp"

my $D_EM   = (1 << 4);   # emphasis                "\fI" .. "\fP"
my $D_BF   = (1 << 5);   # boldface                "\fB" .. "\fP"
my $D_TT   = (1 << 6);   # literal string          "\fC" .. "\fP"

my $D_TAB  = (1 << 7);   # "tscreen" screen shot   ".ts" .. ".te"
my $D_DL   = (1 << 8);   # start defn list         ".dl" .. ".de"
my $D_DT   = (1 << 9);   # dlist term              ".dt"
my $D_DD   = (1 << 10);  # dlist defn              ".dd"
my $D_IL   = (1 << 11);  # itemized list           ".il" .. ".ie"

# Commands sent to print_it() in response to various input strings
my $SP_START_EM    = 1;
my $SP_START_BF    = 2;
my $SP_START_TT    = 3;
my $SP_END_FT      = 4;
my $SP_NEWLINE     = 5;
my $SP_NEWPAR      = 6;
my $SP_END_PAR     = 7;
my $SP_STR         = 8;
my $SP_START_TAB   = 9;
my $SP_END_TAB     = 10;
my $SP_START_DL    = 11;
my $SP_DT          = 12;
my $SP_DD          = 13;
my $SP_END_DD      = 14;
my $SP_END_DL      = 15;
my $SP_START_IL    = 16;
my $SP_END_IL      = 17;
my $SP_END_SECT    = 18;
my $SP_REFER       = 19;

# Types to documentation readable strings:
my %type2human = ("DT_NONE"      => "-none-",
                  "DT_BOOL"      => "boolean",
                  "DT_NUM"       => "number",
                  "DT_LNUM"      => "number (long)",
                  "DT_STR"       => "string",
                  "DT_PATH"      => "path",
                  "DT_CMD_PATH"  => "path",
                  "DT_QUAD"      => "quadoption",
                  "DT_SORT"      => "sort order",
                  "DT_RX"        => "regular expression",
                  "DT_MAGIC"     => "folder magic",
                  "DT_ADDR"      => "e-mail address",
                  "DT_MBCHARTBL" => "string",
                  "DT_L10N_STR"  => "string (localized)",
                  "DT_L10N_RX"   => "regular expression (localized)");

my %string_types = ("DT_STR"       => 1,
                    "DT_RX"        => 1,
                    "DT_ADDR"      => 1,
                    "DT_PATH"      => 1,
                    "DT_CMD_PATH"  => 1,
                    "DT_MBCHARTBL" => 1,
                    "DT_L10N_STR"  => 1,
                    "DT_L10N_RX"   => 1);

my %quad2human = ("MUTT_YES" => "yes",
                  "MUTT_NO"  => "no",
                  "MUTT_ASKYES" => "ask-yes",
                  "MUTT_ASKNO" => "ask-no");

my %bool2human = ("1" => "yes",
                  "0" => "no");

my %sort_maps = ();

# prototypes
# to update:
#   M-1 M-! grep '^sub' makedoc.pl
sub makedoc();
sub flush_doc($);
sub handle_sort_maps();
sub handle_sort_map($);
sub handle_confline($);
sub pretty_default($$$);
sub string_unescape($);
sub string_escape($);
sub print_confline($$$);
sub print_confline_conf($$$);
sub print_conf_strval($);
sub print_confline_man($$$);
sub man_string_escape($);
sub print_man_strval($);
sub print_confline_sgml($$$);
sub print_sgml_id($);
sub print_sgml($);
sub print_sgml_strval($);
sub handle_docline($$);
sub commit_buff($$);
sub print_docline($$$);
sub print_ref($$);
sub print_docline_conf($$$$);
sub print_docline_man($$$$);
sub print_docline_sgml($$$$);


our($opt_c, $opt_m, $opt_s);
getopts('cms');
if ($opt_c) {
  $OutputFormat = $F_CONF;
}
elsif ($opt_m) {
  $OutputFormat = $F_MAN;
}
elsif ($opt_s) {
  $OutputFormat = $F_SGML;
}
else {
  die "$0: no output format specified"
}

makedoc();


sub makedoc() {
  my $line;
  my $active = 0;
  my $docstat = $D_INIT;

  while ($line = <STDIN>) {
    chomp($line);
    $line =~ s/^\s+//;
    if ($line eq '/*++*/') {
      $active = 1;
    }
    elsif ($line eq '/*--*/') {
      $docstat = flush_doc($docstat);
      $active = 0;
    }
    elsif ($line eq '/*+sort+*/') {
      handle_sort_maps();
    }
    elsif ($active) {
      if (($line =~ /^\/\*\*/) || ($line =~ /^\*\*/)) {
        $line =~ s/^[\/*]+\s*//;
        $docstat = handle_docline($line, $docstat);
      }
      elsif ($line =~ /^{/) {
        $line =~ s/^{\s*//;
        $docstat = flush_doc($docstat);
        handle_confline($line);
      }
    }
  }
  flush_doc($docstat);
  print("\n");
}

sub flush_doc($) {
  my ($docstat) = @_;

  if ($docstat & $D_INIT) {
    return $D_INIT;
  }

  if ($docstat & ($D_PA)) {
    $docstat = print_docline($SP_END_PAR, undef, $docstat);
  }

  if ($docstat & ($D_TAB)) {
    $docstat = print_docline($SP_END_TAB, undef, $docstat);
  }

  if ($docstat & ($D_DL)) {
    $docstat = print_docline($SP_END_DL, undef, $docstat);
  }

  if ($docstat & ($D_EM | $D_BF | $D_TT)) {
    $docstat = print_docline($SP_END_FT, undef, $docstat);
  }

  $docstat = print_docline($SP_END_SECT, undef, $docstat);

  $docstat = print_docline($SP_NEWLINE, undef, 0);

  return $D_INIT;
}

####################
# Sort maps handling
####################

sub handle_sort_maps() {
  my $line;
  my $mapname;

  while ($line = <STDIN>) {
    chomp($line);
    $line =~ s/^\s+//;

    if ($line eq '/*-sort-*/') {
      return;
    }

    if (($line =~ /^const\s+struct\s+mapping_t/) &&
        ($line =~ /\/\*\s*(\S+)\s*\*\/\s*$/)) {
      $mapname = $1;
      handle_sort_map($mapname);
    }
  }
}

sub handle_sort_map($) {
  my ($mapname) = @_;
  my $line;
  my $name;
  my $value;

  $sort_maps{$mapname} = {};

  while ($line = <STDIN>) {
    chomp($line);
    $line =~ s/^\s+//;

    if ($line =~ /^{\s*"(\S+)"\s*,\s*(\S+)\s*}/) {
      $name = $1;
      $value = $2;
      if (!exists $sort_maps{$mapname}->{$value}) {
        $sort_maps{$mapname}->{$value} = $name;
      }
    }
    elsif ($line =~ /^{\s*NULL/) {
      return;
    }
  }
}

####################
# Confline handling
####################

sub handle_confline($) {
  my ($line) = @_;

  my $subtype = "";
  my $localized = 0;
  my ($name, $type, $flags, $data, $val) = split(/\s*,\s*/, $line, 5);
  $name =~ s/"//g;

  if ($type =~ /DT_L10N_STR/) {
    $localized = 1;
  }

  $type =~ s/\|(.*)//;
  $subtype = $1;

  if ($localized) {
    if ($type eq "DT_STR") {
      $type = "DT_L10N_STR";
    }
    elsif ($type eq "DT_RX") {
      $type = "DT_L10N_RX";
    }
    else {
      die "Unknown localized type: $type\n"
    }
  }

  $val =~ s/^{\s*\.[lp]\s*=\s*"?//;
  $val =~ s/"?\s*}\s*},\s*$//;
  if ($localized) {
    $val =~ s/^N_\s*\("//;
    $val =~ s/"\)$//;
  }

  # This is a hack to concatenate compile-time constants.
  # (?<!..) is a zero-width negative lookbehind assertion, asserting
  # the first quote isn't preceded by a backslash
  $val =~ s/(?<!\\)"\s+"//g;
  $val = pretty_default($type, $subtype, $val);

  print_confline($name, $type, $val);
}

sub pretty_default($$$) {
  my ($type, $subtype, $val) = @_;

  if ($type eq "DT_QUAD") {
    $val = $quad2human{$val};
  }
  elsif ($type eq "DT_BOOL") {
    $val = $bool2human{$val};
  }
  elsif ($type eq "DT_SORT") {
    my $newval;

    if ($val !~ /^SORT_/) {
      die "Expected SORT_ prefix instead of $val\n";
    }
    if (!$subtype) {
      $subtype = $type;
    }
    if (!$sort_maps{$subtype}) {
      die "Unknown SORT type $subtype\n";
    }
    $newval = $sort_maps{$subtype}->{$val};
    if (!$newval) {
      die "Unknown SORT value $val for map $subtype\n"
    }
    $val = $newval;
  }
  elsif ($type eq "DT_MAGIC") {
    if ($val !~ /^MUTT_/) {
      die "Expected MUTT_ prefix instead of $val\n";
    }
    $val =~ s/^MUTT_//;
    $val = lc $val;
  }
  elsif (exists $string_types{$type}) {
    if ($val eq "0") {
      $val = "";
    }
    else {
      $val = string_unescape($val);
    }
  }

  return $val;
}

sub string_unescape($) {
  my ($val) = @_;

  $val =~ s/\\r/\r/g;
  $val =~ s/\\n/\n/g;
  $val =~ s/\\t/\t/g;
  $val =~ s/\\a/\a/g;
  $val =~ s/\\f/\f/g;
  $val =~ s/\\(.)/$1/g;

  return $val;
}

sub string_escape($) {
  my ($val) = @_;

  $val =~ s/\\/\\\\/g;
  $val =~ s/\r/\\r/g;
  $val =~ s/\n/\\n/g;
  $val =~ s/\t/\\t/g;
  $val =~ s/\f/\\f/g;

  $val =~ s/([^\x20-\x7e])/sprintf("\\%03o", unpack("%C", $1))/ge;

  return $val;
}

sub print_confline($$$) {
  my ($name, $type, $val) = @_;

  if ($type eq "DT_SYN") {
    return;
  }

  if ($OutputFormat == $F_CONF) {
    print_confline_conf($name, $type, $val);
  }
  elsif ($OutputFormat == $F_MAN) {
    print_confline_man($name, $type, $val);
  }
  elsif ($OutputFormat == $F_SGML) {
    print_confline_sgml($name, $type, $val);
  }
}

# conf output format

sub print_confline_conf($$$) {
  my ($name, $type, $val) = @_;

  if (exists $string_types{$type}) {
    print "\n# set ${name}=\"";
    print_conf_strval($val);
    print "\"";
  }
  else {
    print "\n# set ${name}=${val}";
  }

  print "\n#\n# Name: ${name}";
  print "\n# Type: ${type2human{$type}}";
  if (exists $string_types{$type}) {
    print "\n# Default: \"";
    print_conf_strval($val);
    print "\"";
  }
  else {
    print "\n# Default: ${val}";
  }

  print "\n# ";
}

sub print_conf_strval($) {
  my ($val) = @_;

  $val =~ s/(["\\])/\\$1/g;
  $val = string_escape($val);
  print $val;
}

# man output format

sub print_confline_man($$$) {
  my ($name, $type, $val) = @_;

  print "\n.TP\n.B ${name}\n";
  print ".nf\n";
  print "Type: ${type2human{$type}}\n";
  if (exists $string_types{$type}) {
    print "Default: \\(lq";
    print_man_strval($val);
    print "\\(rq\n";
  }
  else {
    print "Default: ";
    print_man_strval($val);
    print "\n";
  }

  print ".fi";
}

sub man_string_escape($) {
  my ($val) = @_;

  $val =~ s/\r/\\\\r/g;
  $val =~ s/\n/\\\\n/g;
  $val =~ s/\t/\\\\t/g;
  $val =~ s/\f/\\\\f/g;

  $val =~ s/([^\x20-\x7e])/sprintf("\\\\%03o", unpack("%C", $1))/ge;

  return $val;
}

sub print_man_strval($) {
  my ($val) = @_;

  $val =~ s/"/\\(rq/g;
  $val =~ s/([\\\-])/\\$1/g;
  $val = man_string_escape($val);
  print $val;
}

# sgml output format

sub print_confline_sgml($$$) {
  my ($name, $type, $val) = @_;

  print "\n<sect2 id=\"";
  print_sgml_id($name);
  print "\">\n<title>";
  print_sgml($name);
  print "</title>\n<literallayout>Type: ${type2human{$type}}";

  if (exists $string_types{$type}) {
    if ($val ne "") {
      print "\nDefault: <quote><literal>";
      print_sgml_strval($val);
      print "</literal></quote>";
    }
    else {
      print "\nDefault: (empty)";
    }
  }
  else {
    print "\nDefault: ${val}"
  }

  print "</literallayout>\n";
}

sub print_sgml_id($) {
  my ($id) = @_;

  $id =~ s/^<//;
  $id =~ s/>$//;
  $id =~ s/_/-/g;

  print $id;
}

sub print_sgml($) {
  my ($val) = @_;

  $val =~ s/&/&amp;/g;
  $val =~ s/</&lt;/g;
  $val =~ s/>/&gt;/g;

  print $val;
}

sub print_sgml_strval($) {
  my ($val) = @_;

  $val = string_escape($val);
  print_sgml($val);
}


###################
# Docline handling
###################

sub handle_docline($$) {
  my ($line, $docstat) = @_;
  my $buff = "";

  if ($line =~ /^\.pp/) {
    return print_docline($SP_NEWPAR, undef, $docstat);
  }
  elsif ($line =~ /^\.ts/) {
    return print_docline($SP_START_TAB, undef, $docstat);
  }
  elsif ($line =~ /^\.te/) {
    return print_docline($SP_END_TAB, undef, $docstat);
  }
  elsif ($line =~ /^\.dl/) {
    return print_docline($SP_START_DL, undef, $docstat);
  }
  elsif ($line =~ /^\.de/) {
    return print_docline($SP_END_DL, undef, $docstat);
  }
  elsif ($line =~ /^\.il/) {
    return print_docline($SP_START_IL, undef, $docstat);
  }
  elsif ($line =~ /^\.ie/) {
    return print_docline($SP_END_IL, undef, $docstat);
  }

  $line =~ s/^\. /  /;

  while ($line ne "") {
    if ($line =~ /^\\\(as/) {
      $buff .= "*";
      substr($line, 0, 4) = "";
    }
    elsif ($line =~ /^\\\(rs/) {
      $buff .= "\\";
      substr($line, 0, 4) = "";
    }
    elsif ($line =~ /^\\fI/) {
      $docstat = commit_buff(\$buff, $docstat);
      $docstat = print_docline($SP_START_EM, undef, $docstat);
      substr($line, 0, 3) = "";
    }
    elsif ($line =~ /^\\fB/) {
      $docstat = commit_buff(\$buff, $docstat);
      $docstat = print_docline($SP_START_BF, undef, $docstat);
      substr($line, 0, 3) = "";
    }
    elsif ($line =~ /^\\fC/) {
      $docstat = commit_buff(\$buff, $docstat);
      $docstat = print_docline($SP_START_TT, undef, $docstat);
      substr($line, 0, 3) = "";
    }
    elsif ($line =~ /^\\fP/) {
      $docstat = commit_buff(\$buff, $docstat);
      $docstat = print_docline($SP_END_FT, undef, $docstat);
      substr($line, 0, 3) = "";
    }
    elsif ($line =~ /^\.dt/) {
      if ($docstat & $D_DD) {
	$docstat = commit_buff(\$buff, $docstat);
	$docstat = print_docline($SP_END_DD, undef, $docstat);
      }
      $docstat = commit_buff(\$buff, $docstat);
      $docstat = print_docline($SP_DT, undef, $docstat);
      substr($line, 0, 4) = "";
    }
    elsif ($line =~ /^\.dd/) {
      if (($docstat & $D_IL) && ($docstat & $D_DD)) {
	$docstat = commit_buff(\$buff, $docstat);
	$docstat = print_docline($SP_END_DD, undef, $docstat);
      }
      $docstat = commit_buff(\$buff, $docstat);
      $docstat = print_docline($SP_DD, undef, $docstat);
      substr($line, 0, 4) = "";
    }
    elsif ($line =~ /^\$\$\$/) {
      print "\$";
      substr($line, 0, 3) = "";
    }
    elsif ($line =~ /^(\$(\$?)([\w\-_<>]*))/) {
      my $whole_ref;
      my $ref;
      my $output_dollar = 0;

      $whole_ref = $1;
      if ($2) {
        $output_dollar = 1;
      }
      $ref = $3;

      $docstat = commit_buff(\$buff, $docstat);
      print_ref($output_dollar, $ref);
      substr($line, 0, length($whole_ref)) = "";
    }
    else {
      $buff .= substr($line, 0, 1);
      substr($line, 0, 1) = "";
    }
  }

  $docstat = commit_buff(\$buff, $docstat);
  return print_docline($SP_NEWLINE, undef, $docstat);
}

sub commit_buff($$) {
  my ($ref_buf, $docstat) = @_;

  if ($$ref_buf ne "") {
    $docstat = print_docline($SP_STR, $$ref_buf, $docstat);
    $$ref_buf = "";
  }

  return $docstat;
}

sub print_docline($$$) {
  my ($special, $str, $docstat) = @_;
  my $onl;

  $onl = ($docstat & ($D_NL | $D_NP));
  $docstat &= ~($D_NL | $D_NP | $D_INIT);

  if ($OutputFormat == $F_CONF) {
    return print_docline_conf($special, $str, $docstat, $onl);
  }
  elsif ($OutputFormat == $F_MAN) {
    return print_docline_man($special, $str, $docstat, $onl);
  }
  elsif ($OutputFormat == $F_SGML) {
    return print_docline_sgml($special, $str, $docstat, $onl);
  }

  return $docstat;
}

sub print_ref($$) {
  my ($output_dollar, $ref) = @_;

  if (($OutputFormat == $F_CONF) || ($OutputFormat == $F_MAN)) {
    if ($output_dollar) {
      print "\$";
    }
    print $ref;
  }
  elsif ($OutputFormat == $F_SGML) {
    print "<link linkend=\"";
    print_sgml_id($ref);
    print "\">";
    if ($output_dollar) {
      print "\$";
    }
    print_sgml($ref);
    print "</link>";
  }
}

my $Continuation = 0;

sub print_docline_conf($$$$) {
  my ($special, $str, $docstat, $onl) = @_;

  if ($special == $SP_END_FT) {
    $docstat &= ~($D_EM|$D_BF|$D_TT);
  }
  elsif ($special == $SP_START_BF) {
    $docstat |= $D_BF;
  }
  elsif ($special == $SP_START_EM) {
    $docstat |= $D_EM;
  }
  elsif ($special == $SP_START_TT) {
    $docstat |= $D_TT;
  }
  elsif ($special == $SP_NEWLINE) {
    if ($onl) {
      $docstat |= $onl;
    }
    else {
      print "\n# ";
      $docstat |= $D_NL;
    }
    if ($docstat & $D_DL) {
      $Continuation++;
    }
  }
  elsif ($special == $SP_NEWPAR) {
    if ($onl & $D_NP) {
      $docstat |= $onl;
    }
    else {
      if (!($onl & $D_NL)) {
        print "\n# ";
      }
      print "\n# ";
      $docstat |= $D_NP;
    }
  }
  elsif ($special == $SP_START_TAB) {
    if (!$onl) {
      print "\n# ";
    }
    $docstat |= $D_TAB;
  }
  elsif ($special == $SP_END_TAB) {
    $docstat &= ~$D_TAB;
    $docstat |= $D_NL;
  }
  elsif ($special == $SP_START_DL) {
    $docstat |= $D_DL;
  }
  elsif ($special == $SP_DT) {
    $Continuation = 0;
    $docstat |= $D_DT;
  }
  elsif ($special == $SP_DD) {
    if ($docstat & $D_IL) {
      print "- ";
    }
    $Continuation = 0;
  }
  elsif ($special == $SP_END_DL) {
    $Continuation = 0;
    $docstat &= ~$D_DL;
  }
  elsif ($special == $SP_START_IL) {
    $docstat |= $D_IL;
  }
  elsif ($special == $SP_END_IL) {
    $Continuation = 0;
    $docstat &= ~$D_IL;
  }
  elsif ($special == $SP_STR) {
    if ($Continuation) {
      $Continuation = 0;
      print "        ";
    }
    print $str;
    if ($docstat & $D_DT) {
      if (length($str) < 8) {
        print " " x (8 - length($str));
      }
      $docstat &= ~$D_DT;
      $docstat |= $D_NL;
    }
  }

  return $docstat;
}

sub print_docline_man($$$$) {
  my ($special, $str, $docstat, $onl) = @_;

  if ($special == $SP_END_FT) {
    print "\\fP";
    $docstat &= ~($D_EM|$D_BF|$D_TT);
  }
  elsif ($special == $SP_START_BF) {
    print "\\fB";
    $docstat |= $D_BF;
    $docstat &= ~($D_EM|$D_TT);
  }
  elsif ($special == $SP_START_EM) {
    print "\\fI";
    $docstat |= $D_EM;
    $docstat &= ~($D_BF|$D_TT);
  }
  elsif ($special == $SP_START_TT) {
    print "\\fB";
    $docstat |= $D_TT;
    $docstat &= ~($D_BF|$D_EM);
  }
  elsif ($special == $SP_NEWLINE) {
    if ($onl) {
      $docstat |= $onl;
    }
    else {
      print "\n";
      $docstat |= $D_NL;
    }
  }
  elsif ($special == $SP_NEWPAR) {
    if ($onl & $D_NP) {
      $docstat |= $onl;
    }
    else {
      if (!($onl & $D_NL)) {
        print "\n";
      }
      print ".IP\n";
      $docstat |= $D_NP;
    }
  }
  elsif ($special == $SP_START_TAB) {
    print "\n.IP\n.EX\n";
    $docstat |= $D_TAB | $D_NL;
  }
  elsif ($special == $SP_END_TAB) {
    print "\n.EE\n";
    $docstat &= ~$D_TAB;
    $docstat |= $D_NL;
  }
  elsif ($special == $SP_START_DL) {
    print ".RS\n.PD 0\n";
    $docstat |= $D_DL;
  }
  elsif ($special == $SP_DT) {
    print ".TP\n";
  }
  elsif ($special == $SP_DD) {
    if ($docstat & $D_IL) {
      print ".TP\n\\(hy ";
    }
    else {
      print "\n";
    }
  }
  elsif ($special == $SP_END_DL) {
    print ".RE\n.PD 1";
    $docstat &= ~$D_DL;
  }
  elsif ($special == $SP_START_IL) {
    print ".RS\n.PD 0\n";
    $docstat |= $D_IL;
  }
  elsif ($special == $SP_END_IL) {
    print ".RE\n.PD 1";
    $docstat &= ~$D_DL;
  }
  elsif ($special == $SP_STR) {
    $str =~ s/\\/\\\\/g;
    $str =~ s/"/\\(rq/g;
    $str =~ s/-/\\-/g;
    $str =~ s/``/\\(lq/g;
    $str =~ s/''/\\(rq/g;
    print $str;
  }

  return $docstat;
}

sub print_docline_sgml($$$$) {
  my ($special, $str, $docstat, $onl) = @_;

  if ($special == $SP_END_FT) {
    if ($docstat & $D_EM) {
      print "</emphasis>";
    }
    if ($docstat & $D_BF) {
      print "</emphasis>";
    }
    if ($docstat & $D_TT) {
      print "</literal>";
    }
    $docstat &= ~($D_EM|$D_BF|$D_TT);
  }
  elsif ($special == $SP_START_BF) {
    print "<emphasis role=\"bold\">";
    $docstat |= $D_BF;
    $docstat &= ~($D_EM|$D_TT);
  }
  elsif ($special == $SP_START_EM) {
    print "<emphasis>";
    $docstat |= $D_EM;
    $docstat &= ~($D_BF|$D_TT);
  }
  elsif ($special == $SP_START_TT) {
    print "<literal>";
    $docstat |= $D_TT;
    $docstat &= ~($D_BF|$D_EM);
  }
  elsif ($special == $SP_NEWLINE) {
    if ($onl) {
      $docstat |= $onl;
    }
    else {
      print "\n";
      $docstat |= $D_NL;
    }
  }
  elsif ($special == $SP_NEWPAR) {
    if ($onl & $D_NP) {
      $docstat |= $onl;
    }
    else {
      if (!($onl & $D_NL)) {
        print "\n";
      }
      if ($docstat & $D_PA) {
        print "</para>\n";
      }
      print "<para>\n";
      $docstat |= $D_NP;
      $docstat |= $D_PA;
    }
  }
  elsif ($special == $SP_END_PAR) {
    print "</para>\n";
    $docstat &= ~$D_PA;
  }
  elsif ($special == $SP_START_TAB) {
    if ($docstat & $D_PA) {
      print "\n</para>\n";
      $docstat &= ~$D_PA;
    }
    print "\n<screen>\n";
    $docstat |= $D_TAB | $D_NL;
  }
  elsif ($special == $SP_END_TAB) {
    print "</screen>";
    $docstat &= ~$D_TAB;
    $docstat |= $D_NL;
  }
  elsif ($special == $SP_START_DL) {
    if ($docstat & $D_PA) {
      print "\n</para>\n";
      $docstat &= ~$D_PA;
    }
    print "\n<informaltable>\n<tgroup cols=\"2\">\n<tbody>\n";
    $docstat |= $D_DL;
  }
  elsif ($special == $SP_DT) {
    print "<row><entry>";
  }
  elsif ($special == $SP_DD) {
    $docstat |= $D_DD;
    if ($docstat & $D_DL) {
      print "</entry><entry>";
    }
    else {
      print "<listitem><para>";
    }
  }
  elsif ($special == $SP_END_DD) {
    if ($docstat & $D_DL) {
      print "</entry></row>\n";
    }
    else {
      print "</para></listitem>";
    }
    $docstat &= ~$D_DD;
  }
  elsif ($special == $SP_END_DL) {
    print "</entry></row></tbody></tgroup></informaltable>\n";
    $docstat &= ~($D_DD|$D_DL);
  }
  elsif ($special == $SP_START_IL) {
    if ($docstat & $D_PA) {
      print "\n</para>\n";
      $docstat &= ~$D_PA;
    }
    print "\n<itemizedlist>\n";
    $docstat |= $D_IL;
  }
  elsif ($special == $SP_END_IL) {
    print "</para></listitem></itemizedlist>\n";
    $docstat &= ~($D_DD|$D_DL);
  }
  elsif ($special == $SP_END_SECT) {
    print "</sect2>";
  }
  elsif ($special == $SP_STR) {
    if ($docstat & $D_TAB) {
      print_sgml($str);
    }
    else {
      $str =~ s/&/&amp;/g;
      $str =~ s/</&lt;/g;
      $str =~ s/>/&gt;/g;
      $str =~ s/``/<quote>/g;
      $str =~ s/''/<\/quote>/g;
      print $str;
    }
  }

  return $docstat;
}
