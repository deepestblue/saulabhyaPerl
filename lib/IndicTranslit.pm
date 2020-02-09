# TODO
# Devanagari: Deal with Vedic anusvara once it comes out

# accept $'s instead of files

package IndicTranslit;

use utf8;
use warnings;
use strict;
use sigtrap;

use Unicode::Normalize qw(check normalize);
use Carp;
use Set::IntSpan;

use FindBin;
use File::Spec;

my $Debugging = 0;

my ($fromLatinData, $toLatinData);

sub debug {
    my $class = shift;

    if (ref $class)  { confess 'Class method called as object method' }

    unless (@_ == 1) { confess 'usage: CLASSNAME->debug(level)' };

    $Debugging = shift;
}

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $self = {};

    $self->{FROM_LANG} = shift;
    $self->{TO_LANG}   = shift;

    unless (exists $self->{FROM_LANG} && exists $self->{TO_LANG}) {
        croak 'Usage: $0 <From Language> <To Language>\n';
    }

    unless (defined $fromLatinData && defined $toLatinData)
    {
        $Debugging and carp "Eval'ing data ...";

        my ($volume,$directories,$file) =
                       File::Spec->splitpath(File::Spec->rel2abs(__FILE__));
        open DATA, '<:utf8', File::Spec->catdir($volume, $directories, 'data.pl') or croak $!;
        {
            # File-slurp mode
            local $/;

            eval <DATA>;
            carp $@ if $@;
        }
        close DATA;
    }

    bless ($self, $class);

    if ($self->{FROM_LANG} eq 'Latin') {
        unless (exists $fromLatinData->{$self->{TO_LANG}}) {
            $self->todo($self->{TO_LANG});
            return;
        }
        $self->{RUN} = sub { return $self->fromLatin(\$fromLatinData->{$self->{TO_LANG}}) } ;
    } elsif ($self->{TO_LANG} eq 'Latin') {
        unless (exists $toLatinData->{$self->{FROM_LANG}}) {
            $self->todo($self->{FROM_LANG});
            return;
        }
        $self->{RUN} = sub { return $self->toLatin(\$toLatinData->{$self->{FROM_LANG}}) } ;
    }

    return unless defined $self->{RUN};

    $Debugging and carp $self->{RUN} . "\n";

    return $self;
}

sub DESTROY {
    my $self = shift;
    $Debugging and carp 'Destroying $self ' . $self;
}

sub from_lang {
    my $self = shift;
    return $self->{FROM_LANG};
}

sub to_lang {
    my $self = shift;
    return $self->{TO_LANG};
}

sub transliterate {
    my $self = shift;

    my ($inputfile, $outputfile) = @_;

    my $ret = 0;

    defined $inputfile  or $inputfile  = '-';
    defined $outputfile or $outputfile = '-';

    local (*INPUT, *OUTPUT);

    open INPUT,  "$inputfile"  or croak $!;
    open OUTPUT, "$outputfile" or croak $!;

    binmode(INPUT, ':utf8');
    binmode(OUTPUT, ':utf8');

    $self->{RUN}();

    $? = 0;
    close INPUT or $! and croak $!;
    $Debugging and $? and carp "$?";
    $ret += $?;

    $? = 0;
    close OUTPUT or $! and croak $!;
    $Debugging and $? and carp "$?";
    $ret += $?;

    return $ret;
}

sub todo {
    my ($self, $lang) = @_;
    $Debugging and carp "$lang ↔ Latin interconversion not implemented. Yet.\n";
}

sub fromLatin {
    my ($self, $translit_map) = @_;

    my ($vowels1, $vowels2, $consonants, $modifiers, $misc, $plosives);

    local $_;

    # Reverse sorted order to ensure reverse prefix order (because of
    # greedy matching later)

    $vowels1 = join('|', map quotemeta, grep { ! $$translit_map->{DIPHTHONG_CONSTITUENTS}{$_} } reverse sort keys %{$$translit_map->{VOWELS}});
    $vowels2 = join('|', map quotemeta, reverse sort keys %{$$translit_map->{DIPHTHONG_CONSTITUENTS}});

    $consonants = join('|', map quotemeta, reverse sort keys %{$$translit_map->{CONSONANTS}});
    $plosives = join('|', map quotemeta, reverse sort keys %{$$translit_map->{PLOSIVES}});

    $modifiers = join('|', map quotemeta, reverse sort keys %{$$translit_map->{MODIFIERS}});
    $misc = join('|', map quotemeta, reverse sort keys %{$$translit_map->{MISC}});

    while (<INPUT>) {
        $_ = normalize('NFD', $_);
        # Order of operations below is ultra-important
        while (s/($misc)/$$translit_map->{MISC}{$1}/) {}
        while (s/($modifiers)/$$translit_map->{MODIFIERS}{$1}/) {}

        while (s/($plosives):/$$translit_map->{CONSONANTS}{$1}$$translit_map->{VOWELMARKS}{''}/) {}
        while (s/a:(i|u)/a$$translit_map->{VOWELS}{$1}/) {}

        while (s/($consonants)($vowels1)/$$translit_map->{CONSONANTS}{$1}$$translit_map->{VOWELMARKS}{$2}/) {}
        while (s/($vowels1)/$$translit_map->{VOWELS}{$1}/) {}

        while (s/($consonants)($vowels2)/$$translit_map->{CONSONANTS}{$1}$$translit_map->{VOWELMARKS}{$2}/) {}
        while (s/($vowels2)/$$translit_map->{VOWELS}{$1}/) {}

        while (s/($consonants)/$$translit_map->{CONSONANTS}{$1}$$translit_map->{VOWELMARKS}{''}/) {}
        print OUTPUT;
    }

    return;
}

sub toLatin {
    my ($self, $translit_map) = @_;

    my $isConsonant = 0;
    my $isPlosive = 0;
    my $isHalfPlosive = 0;
    my $isVowelA = 0;

    while (my $ch = getc INPUT) {
        my $isImplicitA = $isConsonant &&
            ! (Set::IntSpan::member($$translit_map->{INVOWELMARKS}, ord($ch)));
        print OUTPUT 'a' if $isImplicitA;

        if (defined $$translit_map->{CHARMAP}{$ch}) {
            print OUTPUT ':'
                if $isHalfPlosive && $$translit_map->{CHARMAP}{$ch} eq 'h';
            print OUTPUT ':'
                if ($isImplicitA || $isVowelA) && ($$translit_map->{CHARMAP}{$ch} eq 'i' || $$translit_map->{CHARMAP}{$ch} eq 'u');
        }

        $isHalfPlosive = $isPlosive && defined $$translit_map->{CHARMAP}{$ch} && $$translit_map->{CHARMAP}{$ch} eq '';
        $isPlosive = Set::IntSpan::member($$translit_map->{INPLOSIVES}, ord($ch));

        $isVowelA = defined $$translit_map->{CHARMAP}{$ch} && $$translit_map->{CHARMAP}{$ch} eq 'a';
        $isConsonant = Set::IntSpan::member($$translit_map->{INCONSONANTS}, ord($ch));

        print OUTPUT defined $$translit_map->{CHARMAP}{$ch} ? $$translit_map->{CHARMAP}{$ch} : $ch;
    }

    print OUTPUT 'a' if ($isConsonant);

    return;
}

1;
