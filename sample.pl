#!/usr/bin/perl

use warnings;
use strict;
use utf8;

binmode(STDIN,  ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

use IndicTranslit;

#IndicTranslit->debug(1);

sub usage {
    return "Usage: $0 from-script to-script < input > output\n";
}

my ($from, $to) = @ARGV;

defined($from) or die usage();
defined($to) or die usage();

my $tlor = new IndicTranslit($from, $to);
$tlor->transliterate("< -", "> -");
